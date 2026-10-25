from dataclasses import asdict
from contextlib import closing
from datetime import datetime, timedelta, timezone
import json
import os
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit
from uuid import uuid4

import test_api
import jobs
import research
import search_providers


class LocalResearchTests(unittest.IsolatedAsyncioTestCase):
    asyncSetUp = test_api.EquipmentAPITests.asyncSetUp
    request = test_api.EquipmentAPITests.request

    async def ask(self, question, job_id=None):
        payload = dict(question=question, request_key=str(uuid4()))
        if job_id: payload['job_id'] = job_id
        status, job = await self.request('POST', '/jobs/question', payload)
        self.assertEqual(status, 200, job)
        return job

    async def saved_manual(self):
        job = await self.ask('Find the manual for Honda GX160')
        url = 'https://cdn.powerequipment.honda.com/test-gx160.pdf'
        document = dict(url=url, format='pdf', text='Honda GX160 owner manual. Routine maintenance and inspection information. Confirm serial prefix and region before using this original test fixture.', links=[], notice='Original fixture, not a real manufacturer manual.')
        with patch.object(research, 'document', return_value=document):
            status, result = await self.request('POST', '/jobs/' + job['id'] + '/reference', dict(url=url))
        self.assertEqual(status, 200)
        return job, url, result['document']

    async def test_local_first_reuses_saved_manual_across_conversations_without_fetch(self):
        old, url, document = await self.saved_manual()
        with patch.object(research, 'document', side_effect=AssertionError('No network lookup')), patch.object(search_providers.BrowserProvider, 'search', side_effect=AssertionError('No search for a local answer')):
            new = await self.ask('Find the manual for Honda GX160')
        self.assertNotEqual(old['id'], new['id'])
        self.assertTrue(new['research']['local_checked'])
        self.assertFalse(new['research']['needs_online'])
        self.assertIn('saved reference', new['messages'][-1]['content'])
        self.assertTrue(any(source['url'] == url and source['read'] for source in new['sources']))
        with patch.object(research, 'document', side_effect=AssertionError('Use the copied saved source')):
            status, cached = await self.request('POST', '/jobs/' + new['id'] + '/reference', dict(url=url))
        self.assertEqual(status, 200)
        self.assertEqual(cached['document']['retrieved_at'], document['retrieved_at'])
        self.assertTrue(cached['cached'])

    async def test_other_model_is_not_reused(self):
        await self.saved_manual()
        new = await self.ask('Find the manual for Honda GX200')
        self.assertEqual(new['research']['findings'], [])
        self.assertTrue(new['research']['needs_online'])

    async def test_stale_snapshot_requires_further_research(self):
        job, url, document = await self.saved_manual()
        document['retrieved_at'] = (datetime.now(timezone.utc) - timedelta(days=200)).isoformat()
        with closing(jobs.connect()) as connection, connection:
            connection.execute('UPDATE workshop_sources SET document=? WHERE job_id=? AND url=?', (json.dumps(document), job['id'], url))
        new = await self.ask('Find the manual for Honda GX160')
        self.assertTrue(new['research']['findings'][0]['stale'])
        self.assertTrue(new['research']['needs_online'])
        self.assertIn('outdated or insufficient', new['messages'][-1]['content'])

    async def test_user_notes_are_retrieved_and_labelled_observations(self):
        job = await self.ask('Help me plan a fabrication job')
        await self.request('PUT', '/jobs/' + job['id'] + '/state', dict(notes='My measured width is 70 mm; needs rechecking.'))
        job = await self.ask('What are my measurements?', job['id'])
        self.assertIn('70 mm', job['messages'][-1]['content'])
        self.assertIn('observations, not verified', job['messages'][-1]['content'])
        self.assertFalse(job['research']['needs_online'])

    async def test_keyword_matches_do_not_verify_specifications(self):
        await self.saved_manual()
        job = await self.ask('What torque specification for Honda GX160?')
        self.assertTrue(job['research']['needs_online'])
        self.assertIn('cannot give an unverified specification', job['messages'][-1]['content'])

    async def test_browser_plan_is_not_a_successful_search(self):
        with patch.dict(os.environ, GOPHERTECH_SEARCH_PROVIDER='browser'):
            job = await self.ask('Find the manual for Honda GX160')
        plan = job['research']['plan']
        self.assertEqual(plan['status'], 'browser_handoff')
        self.assertEqual(plan['results'], [])
        self.assertFalse(plan['results_retrieved'])
        self.assertIn('GX160', parse_qs(urlsplit(plan['browser_url']).query)['q'][0])

    async def test_unavailable_direct_provider_does_not_silently_fallback_or_call(self):
        with patch.dict(os.environ, GOPHERTECH_SEARCH_PROVIDER='api'):
            status, result = await self.request('POST', '/research/search', dict(query='GX160 manuals'))
        self.assertEqual(status, 200)
        self.assertEqual(result['status'], 'unavailable')
        self.assertFalse(result['results_retrieved'])
        self.assertIsNone(result['browser_url'])

    async def test_disabled_and_invalid_provider_are_clear_and_blank_search_rejected(self):
        for name in ['disabled', 'invalid']:
            with patch.dict(os.environ, GOPHERTECH_SEARCH_PROVIDER=name):
                status, result = await self.request('POST', '/research/search', dict(query='Manual'))
                self.assertEqual(status, 200)
                self.assertEqual(result['status'], 'unavailable')
        status, _ = await self.request('POST', '/research/search', dict(query='  '))
        self.assertEqual(status, 422)

    async def test_assistant_answers_are_not_used_as_knowledge(self):
        await self.ask('Find the manual for Honda GX160')
        second = await self.ask('Find the manual for Honda GX160')
        self.assertEqual(second['research']['findings'], [])
