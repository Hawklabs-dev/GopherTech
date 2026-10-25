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
