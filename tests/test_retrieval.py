"""Original fixtures exercise retrieval, never spend money or contact the internet."""
import os
import unittest
import threading
import time
from unittest.mock import patch
import jobs
import retrieval
import local_ai


class RetrievalTests(unittest.TestCase):
    def test_unsupported_recognized_model_explains_gap_instead_of_repeating_identity(self):
        with patch.dict(os.environ, GOPHERTECH_RESEARCH_NETWORK='1'):
            docs, reply = retrieval.answer(dict(model='TRX200'), 'spark plug', [])
        self.assertEqual(docs, [])
        self.assertIn('recognized TRX200', reply)
        self.assertIn('does not cover this model', reply)
        self.assertNotIn('What is the full model', reply)

    def test_stalled_lookup_returns_and_retries_are_bounded(self):
        release = threading.Event()
        slots = threading.BoundedSemaphore(2)
        calls = []

        def stalled(*args):
            calls.append(True)
            release.wait(2)
            return [], 'late result'

        with patch.dict(os.environ, GOPHERTECH_RESEARCH_NETWORK='1'), patch.object(retrieval, '_lookup_slots', slots), patch.object(retrieval, 'LOOKUP_TIMEOUT', .03), patch.object(retrieval, '_answer', side_effect=stalled):
            try:
                started = time.monotonic()
                for _ in range(2):
                    docs, reply = retrieval.answer({'model':'GX160'}, 'manual', [])
                    self.assertEqual(docs, [])
                    self.assertIn('timed out', reply)
                _, reply = retrieval.answer({'model':'GX160'}, 'manual', [])
                self.assertIn('still busy', reply)
                self.assertLess(time.monotonic() - started, .5)
                self.assertEqual(len(calls), 2)
            finally:
                release.set()
                deadline = time.monotonic() + 1
                while slots._value != 2 and time.monotonic() < deadline:
                    time.sleep(.005)
        self.assertEqual(slots._value, 2)

    def test_screenshot_typo_and_machine_switch(self):
        first = jobs.route_question({}, 'I have a john deer riding mower where is the oil drain plug')
        self.assertEqual(first['brand'], 'John Deere')
        self.assertEqual(first['intent'], 'manual')
        follow = jobs.route_question(first, 'D120')
        self.assertEqual(follow['model'], 'D120')
        different = jobs.route_question(follow, 'find specs on a turf ranger 2007')
        self.assertNotIn('brand', different)
        self.assertEqual(different['model'], 'Turf Ranger')
        self.assertEqual(different['intent'], 'specification')

    def test_real_pipeline_serial_selection_and_citation(self):
        index = dict(url='https://engines.honda.com/example', format='html', text='Model listing', links=[dict(url='https://cdn.powerequipment.honda.com/matched.pdf', applicability='GCACK 1000001 1125014')])
        manual = dict(url='https://cdn.powerequipment.honda.com/matched.pdf', format='pdf', text='Honda GX160 original test fixture.\fOil drain: this original fixture describes checking the illustrated drain point with the engine stopped and cool.', links=[])
        context = dict(brand='Honda',model='GX160',serial='GCACK-1000002',intent='manual')
        with patch.dict(os.environ, GOPHERTECH_RESEARCH_NETWORK='1'), patch('research.document', side_effect=[index,manual]) as fetch, patch('local_ai.select',return_value=[0]):
            docs, answer = retrieval.answer(context, 'Where is the oil drain?', [dict(kind='Model lookup',url=index['url'])])
        self.assertEqual(fetch.call_count,2)
        self.assertIn('could not verify', answer)
        self.assertNotIn('Oil drain:', answer)
        self.assertEqual(docs[-1]['url'], manual['url'])
        self.assertEqual(docs[-1]['saved_context']['serial'],'GCACK-1000002')

    def test_unknown_serial_does_not_guess_pdf(self):
        index = dict(url='https://engines.honda.com/example', text='listing',links=[dict(url='https://cdn.powerequipment.honda.com/wrong.pdf',applicability='GCACK 1000001 1125014')])
        with patch.dict(os.environ,GOPHERTECH_RESEARCH_NETWORK='1'), patch('research.document',return_value=index) as fetch:
            docs, answer = retrieval.answer(dict(model='GX160'), 'manual', [dict(kind='Model lookup',url=index['url'])])
        self.assertEqual(fetch.call_count,1)
        self.assertIn('complete serial', answer)

    def test_failed_lookup_is_honest(self):
        with patch.dict(os.environ,GOPHERTECH_RESEARCH_NETWORK='1'), patch('research.document',side_effect=OSError('offline')):
            docs, answer = retrieval.answer(dict(model='GX160'),'manual',[dict(kind='Model lookup',url='https://engines.honda.com/example')])
        self.assertEqual(docs,[])
        self.assertIn('No answer or specification has been verified',answer)

    def test_model_unavailable_keeps_reference_extract(self):
        self.assertIsNone(local_ai.select('test',[]))

    def test_aliases_and_new_machine_clear_old_observations(self):
        old=dict(brand='Honda',model='GX160',serial='GCACK-1000002',fuel='petrol',fuel_observation='fresh fuel',symptom='no start',year='2007')
        new=jobs.route_question(old, 'My other mower is a JD D120 and runs rough')
        self.assertEqual(new['brand'],'John Deere')
        self.assertEqual(new['model'],'D120')
        self.assertNotIn('serial',new)
        self.assertNotIn('fuel_observation',new)
        self.assertNotIn('year',new)
        self.assertEqual(new['intent'],'troubleshoot')

    def test_model_followup_and_style_keep_current_identity(self):
        first=jobs.route_question({}, 'JD mower wont start')
        follow=jobs.route_question(first, 'model is D120')
        self.assertEqual(follow['model'],'D120')
        self.assertEqual(follow['intent'],'troubleshoot')
        guided=jobs.route_question(follow, 'Walk me through it')
        self.assertEqual(guided['response_style'],'guided')
        self.assertEqual(guided['model'],'D120')

    def test_conflicting_pdf_matches_are_not_selected(self):
        index=dict(url='https://engines.honda.com/example',text='listing',links=[dict(url='https://cdn.powerequipment.honda.com/'+name+'.pdf',applicability='GCACK 1000001 1125014') for name in ('one','two')])
        with patch.dict(os.environ,GOPHERTECH_RESEARCH_NETWORK='1'), patch('research.document',return_value=index) as fetch:
            docs,answer=retrieval.answer(dict(model='GX160',serial='GCACK-1000002'),'oil drain',[dict(kind='Model lookup',url=index['url'])])
        self.assertEqual(fetch.call_count,1)
        self.assertIn('More than one manual',answer)

    def test_unmatched_full_serial_does_not_repeat_missing_serial_question(self):
        index=dict(url='https://engines.honda.com/example',text='listing',links=[])
        with patch.dict(os.environ,GOPHERTECH_RESEARCH_NETWORK='1'), patch('research.document',return_value=index):
            _,answer=retrieval.answer(dict(model='GX160',serial='GCACK-9999999'),'manual',[dict(kind='Model lookup',url=index['url'])])
        self.assertIn('could not match',answer)
        self.assertNotIn('What is the complete serial',answer)

    def test_natural_serial_followups_and_corrections(self):
        first=jobs.route_question({},'Find manual Honda GX160 GCACK')
        full=jobs.route_question(first,'1000002')
        self.assertEqual(full['serial'],'GCACK-1000002')
        corrected=jobs.route_question(full,'Actually GCACK1000003')
        self.assertEqual(corrected['serial'],'GCACK1000003')
        self.assertEqual(corrected['task_question'],first['task_question'])

    def test_engine_name_alone_is_not_an_answer_to_technical_question(self):
        pdf=dict(url='https://engines.honda.com/fixture.pdf',text='Honda GX160 owner information. This fixture does not contain the requested technical procedure.')
        with patch('local_ai.select',return_value=None):
            answer=retrieval.extract(pdf,'Honda GX160 oil drain',dict(brand='Honda',model='GX160'))
        self.assertIn('could not verify',answer)

    def test_long_paragraph_is_not_cut_into_an_incomplete_instruction(self):
        pdf=dict(url='https://engines.honda.com/fixture.pdf',text='Oil drain '+('original fixture words '*80))
        with patch('local_ai.select',return_value=None):
            answer=retrieval.extract(pdf,'oil drain',{})
        self.assertIn('could not verify',answer)

    def test_same_brand_new_unrecognized_model_replaces_identity_and_task(self):
        old = dict(brand='Honda', model='GX160', serial='GCACK-1000002', region='Canada', year='2010', intent='manual', task_question='GX160 oil drain', fuel_observation='fresh fuel')
        question = '2004 honda trx 200 atv, need to know what type of spark plug it takes'
        new = jobs.route_question(old, question)
        self.assertEqual(new['model'], 'TRX200')
        self.assertEqual(new['year'], '2004')
        self.assertEqual(new['intent'], 'specification')
        self.assertEqual(new['task_question'], question)
        for key in ('serial', 'region', 'fuel_observation'):
            self.assertNotIn(key, new)
        self.assertFalse(any('gx160' in s['url'].lower() for s in jobs.matching_sources(new)))

    def test_brand_with_unknown_machine_cannot_inherit_model(self):
        new = jobs.route_question(dict(brand='Honda', model='GX160', task_question='old manual'), 'My Honda Foreman ATV needs a sparkplug')
        self.assertNotIn('model', new)
        self.assertEqual(new['intent'], 'specification')
        self.assertNotEqual(new['task_question'], 'old manual')

    def test_wrong_model_and_scrambled_text_are_not_instructions(self):
        pdf = dict(url='https://engines.honda.com/fixture.pdf', text='Honda GX160. Gasoline is highly flammable and 5. Install spark plug carefully explosive.')
        answer = retrieval.extract(pdf, 'spark plug', dict(model='TRX200'))
        self.assertIn('does not establish a match', answer)
        self.assertNotIn('Install spark plug', answer)
        pdf['text'] = pdf['text'].replace('GX160', 'TRX200')
        answer = retrieval.extract(pdf, 'spark plug', dict(model='TRX200'))
        self.assertIn('could not verify', answer)
        self.assertNotIn('Install spark plug', answer)
