"""Original fixtures exercise retrieval, never spend money or contact the internet."""
import os
import unittest
from unittest.mock import patch
import jobs
import retrieval
import local_ai


class RetrievalTests(unittest.TestCase):
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
        manual = dict(url='https://cdn.powerequipment.honda.com/matched.pdf', format='pdf', text='Original test fixture.\fOil drain: this original fixture describes checking the illustrated drain point with the engine stopped and cool.', links=[])
        context = dict(brand='Honda',model='GX160',serial='GCACK-1000002',intent='manual')
        with patch.dict(os.environ, GOPHERTECH_RESEARCH_NETWORK='1'), patch('research.document', side_effect=[index,manual]) as fetch, patch('local_ai.select',return_value=[0]):
            docs, answer = retrieval.answer(context, 'Where is the oil drain?', [dict(kind='Model lookup',url=index['url'])])
        self.assertEqual(fetch.call_count,2)
        self.assertIn('Page 2',answer)
        self.assertIn(manual['url'],answer)
        self.assertIn('Local AI selected',answer)
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
