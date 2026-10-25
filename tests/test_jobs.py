import json
from uuid import uuid4
import unittest
from unittest.mock import patch

import test_api
import database
import research


class JobTests(unittest.IsolatedAsyncioTestCase):
    asyncSetUp = test_api.EquipmentAPITests.asyncSetUp
    request = test_api.EquipmentAPITests.request

    async def ask(self, question, job_id=None, request_key=None):
        payload = dict(question=question, request_key=request_key or str(uuid4()))
        if job_id:
            payload['job_id'] = job_id
        status, job = await self.request('POST', '/jobs/question', payload)
        self.assertEqual(status, 200, job)
        return job

    async def test_question_followup_and_observations_keep_context(self):
        job = await self.ask("My tractor turns over but won't start.")
        self.assertIn('petrol or diesel', job['messages'][-1]['content'])
        job = await self.ask('Honda GX160 petrol in Canada', job['id'])
        self.assertEqual(job['context']['model'], 'GX160')
        self.assertEqual(job['context']['region'], 'Canada')
        self.assertEqual(job['context']['intent'], 'troubleshoot')
        self.assertIn('Possible causes', job['messages'][-1]['content'])
        job = await self.ask('Fresh fuel, tank full, normal cranking', job['id'])
        self.assertIn('fuel observation is saved', job['messages'][-1]['content'])
        self.assertEqual(len(job['messages']), 6)
        self.assertFalse(job['ai_enabled'])

    async def test_diesel_does_not_get_petrol_ignition_checklist(self):
        job = await self.ask("Kubota diesel turns over but won't start")
        self.assertIn('Do not loosen high-pressure fuel lines', job['messages'][-1]['content'])
        self.assertNotIn('spark plug', job['messages'][-1]['content'])
        self.assertEqual(job['sources'], [])

    async def test_manual_sources_prefer_model_and_no_unrelated_brands(self):
        job = await self.ask('Find the manual for my Honda GX160')
        self.assertIn('gx160', job['sources'][0]['url'])
        self.assertTrue(all('honda' in item['url'] for item in job['sources']))
        self.assertTrue(all(not item['read'] for item in job['sources']))
        self.assertIn('No matching owner document has been verified', job['messages'][-1]['content'])

    async def test_missing_hydraulic_manual_and_unknown_provider_are_honest(self):
        job = await self.ask('Find a hydraulic diagram for my Kubota model L2501')
        self.assertEqual(job['sources'], [])
        self.assertIn('do not have a matching manufacturer source', job['messages'][-1]['content'])
        self.assertIn('No matching hydraulic document has been verified', job['messages'][-1]['content'])

    async def test_part_fabrication_and_specification_routing(self):
        for question, intent in [('Help identify this replacement part', 'parts'), ('Help me plan a fabrication job', 'fabrication'), ('What torque should I use for this bolt?', 'specification')]:
            job = await self.ask(question)
            self.assertEqual(job['context']['intent'], intent)
        self.assertIn('cannot give an unverified specification', job['messages'][-1]['content'])

    async def test_exploded_views_and_parts_lists_route_to_documents(self):
        for phrase in ['exploded view', 'parts list', 'wiring diagram', 'diagnostic procedure']:
            job = await self.ask('Find the ' + phrase + ' for Honda GX160')
            self.assertEqual(job['context']['intent'], 'manual')
            self.assertIn('No matching', job['messages'][-1]['content'])

    async def test_question_retry_and_conflict(self):
        key = str(uuid4())
        first = await self.ask('Honda GX160 manual', request_key=key)
        second = await self.ask('Honda GX160 manual', request_key=key)
        self.assertEqual(first['id'], second['id'])
        self.assertEqual(len(second['messages']), 2)
        status, _ = await self.request('POST', '/jobs/question', dict(question='Other question', request_key=key))
        self.assertEqual(status, 409)

    async def test_serial_and_region_followup_are_not_asked_again(self):
        job = await self.ask('Find the manual for my Honda GX160')
        job = await self.ask('GCACK-1126000 Canada', job['id'])
        self.assertEqual(job['context']['serial'], 'GCACK-1126000')
        self.assertEqual(job['context']['region'], 'Canada')
        self.assertNotIn('What is the serial', job['messages'][-1]['content'])
        self.assertEqual(job['context']['model'], 'GX160')

    async def test_jobs_notes_and_parts_survive_reinitialization(self):
        job = await self.ask('Help me plan a fabrication job')
        url = '/jobs/' + job['id']
        status, _ = await self.request('PUT', url + '/state', dict(notes='Measured in mm — keep these notes', parts=['Qty 2: bracket blanks']))
        self.assertEqual(status, 200)
        database.initialize_database()
        status, reopened = await self.request('GET', url)
        self.assertEqual(status, 200)
        self.assertEqual(reopened['notes'], 'Measured in mm — keep these notes')
        self.assertEqual(reopened['parts'], ['Qty 2: bracket blanks'])
        self.assertEqual(reopened['messages'], job['messages'])
        _, listing = await self.request('GET', '/jobs')
        self.assertEqual(listing['jobs'][0]['id'], job['id'])

    async def test_readable_source_snapshot_survives_restart_without_refetch(self):
        job = await self.ask('Find the manual for my Honda GX160')
        url = job['sources'][0]['url']
        fixture = dict(url=url, format='html', text='Original fixture manual text', links=[], notice='Fixture, not real repair instructions')
        with patch.object(research, 'document', return_value=fixture):
            status, saved = await self.request('POST', '/jobs/' + job['id'] + '/reference', dict(url=url))
        self.assertEqual(status, 200)
        self.assertTrue(saved['job']['sources'][0]['read'])
        database.initialize_database()
        with patch.object(research, 'document', side_effect=AssertionError('Must use saved snapshot')):
            status, reopened = await self.request('POST', '/jobs/' + job['id'] + '/reference', dict(url=url))
        self.assertEqual(status, 200)
        self.assertEqual(reopened['document']['text'], fixture['text'])
        self.assertTrue(reopened['cached'])

    async def test_failed_document_does_not_claim_read_or_discard_job(self):
        from fastapi import HTTPException
        job = await self.ask('Find the manual for my Honda GX160')
        with patch.object(research, 'document', side_effect=HTTPException(502, 'Manufacturer unavailable')):
            status, _ = await self.request('POST', '/jobs/' + job['id'] + '/reference', dict(url=job['sources'][0]['url']))
        self.assertEqual(status, 502)
        _, reopened = await self.request('GET', '/jobs/' + job['id'])
        self.assertTrue(all(not entry['read'] for entry in reopened['sources']))
        self.assertEqual(reopened['messages'], job['messages'])

    async def test_blank_question_and_state_limits_rejected(self):
        for text in ['   ', 'x' * 4001]:
            status, _ = await self.request('POST', '/jobs/question', dict(question=text, request_key=str(uuid4())))
            self.assertEqual(status, 422)
        job = await self.ask('Notes')
        status, _ = await self.request('PUT', '/jobs/' + job['id'] + '/state', dict(parts=['x' * 4001]))
        self.assertEqual(status, 422)
        status, _ = await self.request('GET', '/jobs/' + str(uuid4()))
        self.assertEqual(status, 404)

    def test_manual_link_retains_real_serial_table_context(self):
        parser = research.ReferenceHTML('https://engines.honda.com/manual')
        parser.feed('<table><tr><td>GCACK</td><td>1125015 through 1253941</td><td><a href="https://cdn.powerequipment.honda.com/manual.pdf">Download</a></td></tr></table>')
        self.assertIn('GCACK', parser.links[0]['applicability'])
        self.assertIn('1125015 through 1253941', parser.links[0]['applicability'])

    def test_reader_filters_navigation_and_prioritizes_reported_prefix(self):
        import jobs
        doc = dict(links=[dict(url='https://engines.honda.com/about', title='About'),
                          dict(url='https://engines.honda.com/other.pdf', title='Manual'),
                          dict(url='https://engines.honda.com/engine.pdf', title='Manual', applicability='GCACK 1125015 through 1253941')])
        result = jobs.focus_document(doc, dict(serial='GCACK-1126000'))
        self.assertEqual(len(result['links']), 2)
        self.assertTrue(result['links'][0]['url'].endswith('engine.pdf'))

class FieldConversationTests(unittest.IsolatedAsyncioTestCase):
    asyncSetUp = JobTests.asyncSetUp
    request = JobTests.request
    ask = JobTests.ask
    async def test_three_mower_jobs_remain_separate_after_restart(self):
        descriptions=['JD D120 wont start', 'Honda GX160 runs rough', 'Kubota diesel not starting']
        saved=[]
        for index,question in enumerate(descriptions):
            job=await self.ask(question)
            status,_=await self.request('PUT','/jobs/'+job['id']+'/state',dict(notes='Mower '+str(index+1)+' observation',parts=['Item '+str(index+1)]))
            self.assertEqual(status,200)
            saved.append(job)
        database.initialize_database()
        for index,job in enumerate(saved):
            status,reopened=await self.request('GET','/jobs/'+job['id'])
            self.assertEqual(status,200)
            self.assertEqual(reopened['messages'][0]['content'],descriptions[index])
            self.assertEqual(reopened['notes'],'Mower '+str(index+1)+' observation')
            self.assertEqual(reopened['parts'],['Item '+str(index+1)])
            follow=await self.ask('What are my notes?',job['id'])
            self.assertIn('Mower '+str(index+1)+' observation',follow['messages'][-1]['content'])

    async def test_online_limitation_preserves_useful_symptom_guidance(self):
        import os
        with patch.dict(os.environ,GOPHERTECH_RESEARCH_NETWORK='1'):
            job=await self.ask('JD mower wont start')
        answer=job['messages'][-1]['content']
        self.assertIn('Next useful check',answer)
        self.assertIn('Reference lookup',answer)
        self.assertEqual(job['context']['brand'],'John Deere')
