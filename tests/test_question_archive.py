"""Regression cases from the shop conversation and durable archiving."""
from uuid import uuid4
import unittest
import jobs
import test_api
import search_providers


class RoutingTests(unittest.TestCase):
    def test_spoken_atv_model_replaces_engine_and_task(self):
        old = jobs.route_question({}, 'Honda GX160 oil drain plug')
        plug = jobs.route_question(old, '2004 honda trx 200 atv, what spark plug does it take?')
        self.assertEqual(plug['model'], 'TRX200')
        wheel = jobs.route_question(plug, 'my honda 200 trx atv has bad rubber on the front wheels what is the specs for the lug spacing?')
        self.assertEqual(wheel['model'], 'TRX200')
        self.assertEqual(wheel['intent'], 'specification')
        self.assertNotIn('document_kind', wheel)
        self.assertNotIn('spark plug', wheel['task_question'])
        query = search_providers.targeted_query(wheel, wheel['last_question'])
        self.assertIn('TRX200', query)
        self.assertIn('lug spacing', query)
        self.assertNotIn('oil drain', query)


class ArchiveTests(unittest.IsolatedAsyncioTestCase):
    asyncSetUp = test_api.EquipmentAPITests.asyncSetUp
    request = test_api.EquipmentAPITests.request

    async def test_archive_is_durable_and_reopenable(self):
        status, job = await self.request('POST', '/jobs/question', dict(question='Honda TRX200 spark plug', request_key=str(uuid4())))
        self.assertEqual(status, 200)
        status, archived = await self.request('POST', '/jobs/' + job['id'] + '/archive', {})
        self.assertEqual(status, 200)
        self.assertTrue(archived['archived_at'])
        self.assertEqual(archived['messages'], job['messages'])
        active = jobs.list_jobs(include_archived=False)
        self.assertFalse(active['jobs'])
        _, saved = await self.request('GET', '/jobs')
        self.assertEqual(saved['jobs'][0]['id'], job['id'])
        _, reopened = await self.request('GET', '/jobs/' + job['id'])
        self.assertEqual(reopened['messages'], job['messages'])
