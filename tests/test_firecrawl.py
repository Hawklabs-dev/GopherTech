"""Source reading, model isolation and replay/reopen checks without paid calls."""
from dataclasses import asdict
from datetime import datetime, timezone
import io
import json
import os
import threading
import unittest
import urllib.error
from unittest.mock import patch
from uuid import uuid4

import firecrawl_client
import local_ai
import search_providers
import test_api
import web_research


def result(model='GX160', text=None, kind='markdown'):
    text = text or f'Honda {model} maintenance information.\n\nFor the Honda {model}, inspect the oil level with the engine stopped and sitting level before operation. Confirm the correct manual and serial range.'
    row = dict(url=f'https://engine.example.com/{model.lower()}' + ('.pdf' if kind == 'pdf' else ''),
               title=f'Honda {model} maintenance', text=text, read=True, format=kind,
               retrieved_at=datetime.now(timezone.utc).isoformat())
    return search_providers.SearchResponse('firecrawl', 'retrieved', 'fixture query', 'Source read',
                                           results=[row], results_retrieved=True)


class FirecrawlClientTests(unittest.TestCase):
    def setUp(self):
        firecrawl_client._cache.clear()
        self.key = patch.object(firecrawl_client, 'api_key', return_value='')
        self.key.start()
        self.addCleanup(self.key.stop)

    def test_reads_content_in_grouped_and_legacy_response_shapes(self):
        row = dict(url='https://engine.example.com/manual', title='Manual', markdown='Original source text', metadata={'statusCode':200})
        for data in ({'web':[row]}, [row]):
            firecrawl_client._cache.clear()
            with patch.object(firecrawl_client, '_post', return_value={'success':True, 'data':data}) as request:
                response = firecrawl_client.search('engine manual')
            self.assertTrue(response.results_retrieved)
            self.assertTrue(response.results[0]['read'])
            self.assertEqual(response.results[0]['text'], row['markdown'])
            self.assertEqual(request.call_args.args[0]['limit'], 3)
            self.assertEqual(request.call_args.args[0]['scrapeOptions']['formats'], ['markdown'])

    def test_failed_scrape_is_not_reported_as_a_read_page(self):
        row = dict(url='https://engine.example.com/manual', markdown='Blocked', metadata={'statusCode':403})
        with patch.object(firecrawl_client, '_post', return_value={'success':True, 'data':{'web':[row]}}):
            response = firecrawl_client.search('manual')
        self.assertFalse(response.results[0]['read'])
        self.assertEqual(response.results[0]['text'], '')

    def test_limits_auth_and_network_errors_are_explicit_without_retry(self):
        for code, state in ((401,'needs_connection'), (402,'limit_reached'), (403,'needs_connection'), (429,'limit_reached'), (500,'unavailable')):
            with patch.object(firecrawl_client, '_post', side_effect=urllib.error.HTTPError('https://api.firecrawl.dev', code, 'error', {}, io.BytesIO())) as request:
                response = firecrawl_client.search('manual')
            self.assertEqual(response.status, state)
            self.assertFalse(response.results_retrieved)
            self.assertEqual(request.call_count, 1)

    def test_rejects_local_credentialed_and_injectable_urls(self):
        for url in ('http://engine.example.com', 'https://127.0.0.1/x', 'https://127.1/x', 'https://10.0.0.1/x', 'https://shop.local/x', 'https://a:b@engine.example.com', 'https://engine.example.com:8000/x', 'https://engine.example.com/]x', 'https://engine.example.com/\nx'):
            self.assertFalse(firecrawl_client.public_url(url), url)
        self.assertTrue(firecrawl_client.public_url('https://engine.example.com/manual?q=GX160'))

    def test_planning_never_searches_or_reads_pages(self):
        with patch.dict(os.environ, GOPHERTECH_SEARCH_PROVIDER='firecrawl'), patch.object(firecrawl_client, '_post', side_effect=AssertionError('No request from planning')):
            response = search_providers.search_plan({'model':'GX160'}, 'manual')
        self.assertEqual(response['provider'], 'firecrawl')
        self.assertFalse(response['results_retrieved'])


class WebResearchTests(unittest.TestCase):
    def compose(self, response, model='GX160', intent='troubleshoot'):
        with patch.object(local_ai, 'select', return_value=[0]):
            return web_research.compose({'brand':'Honda','model':model,'intent':intent}, 'How do I inspect the oil?', response)

    def test_other_model_is_not_evidence(self):
        docs, reply, report = self.compose(result('GX390'))
        self.assertEqual(docs, [])
        self.assertEqual(report['pages_read'], 0)
        self.assertIn('could not read a source', reply)

    def test_pdf_table_text_is_saved_for_inspection_never_quoted_as_an_answer(self):
        docs, reply, report = self.compose(result(kind='pdf', text='Honda GX160\n\nOil mixed table row 12345 wrong columns.'), intent='specification')
        self.assertEqual(len(docs), 1)
        self.assertNotIn('12345', reply)
        self.assertEqual(report['selection'], 'none')

    def test_local_ai_selects_real_source_text_without_creating_a_fact(self):
        docs, reply, report = self.compose(result())
        self.assertEqual(report['selection'], 'local_ai')
        self.assertIn('engine stopped', reply)
        self.assertIn('Check model', reply)
        self.assertEqual(docs[0]['verification_status'], 'source read; applicability unverified')

    def test_ai_abstention_does_not_become_a_keyword_answer(self):
        with patch.object(local_ai, 'select', return_value=[]):
            docs, reply, report = web_research.compose({'model':'GX160'}, 'inspect oil', result())
        self.assertEqual(len(docs), 1)
        self.assertIn('could not find a passage', reply)
        self.assertNotIn('engine stopped', reply)

    def test_manufacturer_manual_takes_priority_over_video_transcript(self):
        response = result()
        response.results[0]['url'] = 'https://www.youtube.com/watch?v=fixture'
        primary = result(kind='pdf').results[0]
        primary['url'] = 'https://www.honda-engines-eu.com/manual.pdf'
        response.results.append(primary)
        docs, reply, _ = self.compose(response)
        self.assertEqual([doc['url'] for doc in docs], [primary['url']])
        self.assertNotIn('engine stopped', reply)
        self.assertIn('source manual', reply)


class FirecrawlQuestionTests(unittest.IsolatedAsyncioTestCase):
    asyncSetUp = test_api.EquipmentAPITests.asyncSetUp
    request = test_api.EquipmentAPITests.request

    async def test_question_fetches_reads_saves_replays_and_reopens_offline(self):
        payload = dict(question='How do I inspect the oil on a Honda GX160?', request_key=str(uuid4()))
        with patch.dict(os.environ, GOPHERTECH_SEARCH_PROVIDER='firecrawl', GOPHERTECH_RESEARCH_NETWORK='1'), patch.object(firecrawl_client, 'search', return_value=result()) as search, patch.object(local_ai, 'select', return_value=[0]):
            code, job = await self.request('POST', '/jobs/question', payload)
            self.assertEqual(code, 200)
            self.assertIn('engine stopped', job['messages'][-1]['content'])
            self.assertTrue(job['ai_enabled'])
            self.assertEqual(len(job['messages'][-1]['evidence']), 1)
            self.assertNotIn('text', job['research']['plan']['results'][0])
            _, replay = await self.request('POST', '/jobs/question', payload)
            self.assertEqual(len(replay['messages']), 2)
            self.assertEqual(search.call_count, 1)
        url = job['messages'][-1]['evidence'][0]['url']
        with patch.object(firecrawl_client, 'search', side_effect=AssertionError('No network while reopening')):
            code, source = await self.request('POST', '/jobs/' + job['id'] + '/reference', {'url':url})
            self.assertEqual(code, 200)
            self.assertTrue(source['cached'])
            self.assertIn('engine stopped', source['document']['text'])

    async def test_switching_machine_keeps_old_evidence_on_old_exchange(self):
        with patch.dict(os.environ, GOPHERTECH_SEARCH_PROVIDER='firecrawl', GOPHERTECH_RESEARCH_NETWORK='1'), patch.object(firecrawl_client, 'search', return_value=result()), patch.object(local_ai, 'select', return_value=[0]):
            _, first = await self.request('POST', '/jobs/question', {'question':'How do I inspect Honda GX160 oil?', 'request_key':str(uuid4())})
            _, second = await self.request('POST', '/jobs/question', {'question':'Honda TRX200 spark plug', 'job_id':first['id'], 'request_key':str(uuid4())})
        self.assertEqual(second['context']['model'], 'TRX200')
        self.assertEqual(second['messages'][-1]['evidence'], [])
        self.assertEqual(len(second['messages'][1]['evidence']), 1)

    async def test_saved_firecrawl_source_is_reused_without_another_search(self):
        with patch.dict(os.environ, GOPHERTECH_SEARCH_PROVIDER='firecrawl', GOPHERTECH_RESEARCH_NETWORK='1'), patch.object(firecrawl_client, 'search', return_value=result()) as search, patch.object(local_ai, 'select', return_value=[0]):
            _, first = await self.request('POST', '/jobs/question', {'question':'How do I inspect Honda GX160 oil?', 'request_key':str(uuid4())})
            _, second = await self.request('POST', '/jobs/question', {'question':'How do I inspect Honda GX160 oil?', 'request_key':str(uuid4())})
        self.assertEqual(search.call_count, 1)
        self.assertNotEqual(first['id'], second['id'])
        self.assertIn('From a saved source (not refreshed)', second['messages'][-1]['content'])
        self.assertIn('engine stopped', second['messages'][-1]['content'])
        self.assertEqual(len(second['messages'][-1]['evidence']), 1)

    async def test_limit_is_saved_as_a_limitation_without_fake_sources(self):
        limited = search_providers.SearchResponse('firecrawl', 'limit_reached', 'fixture', 'Free credits exhausted; no paid fallback.')
        with patch.dict(os.environ, GOPHERTECH_SEARCH_PROVIDER='firecrawl', GOPHERTECH_RESEARCH_NETWORK='1'), patch.object(firecrawl_client, 'search', return_value=limited):
            code, job = await self.request('POST', '/jobs/question', {'question':'Honda GX160 maintenance', 'request_key':str(uuid4())})
        self.assertEqual(code, 200)
        self.assertEqual(job['research']['plan']['status'], 'limit_reached')
        self.assertIn('Free credits exhausted', job['messages'][-1]['content'])
        self.assertEqual(job['messages'][-1]['evidence'], [])

    async def test_timed_out_worker_cannot_replace_saved_answer(self):
        release, finished = threading.Event(), threading.Event()

        def stalled(*args):
            release.wait(2)
            finished.set()
            return [], 'LATE ANSWER', {'provider':'firecrawl'}

        with patch.dict(os.environ, GOPHERTECH_SEARCH_PROVIDER='firecrawl', GOPHERTECH_RESEARCH_NETWORK='1'), patch.object(web_research, 'LOOKUP_TIMEOUT', .03), patch.object(web_research, '_answer', side_effect=stalled):
            try:
                _, job = await self.request('POST', '/jobs/question', {'question':'Honda GX160 maintenance', 'request_key':str(uuid4())})
                self.assertIn('timed out', job['messages'][-1]['content'])
            finally:
                release.set()
                finished.wait(1)
        _, reopened = await self.request('GET', '/jobs/' + job['id'])
        self.assertEqual(reopened['messages'], job['messages'])
