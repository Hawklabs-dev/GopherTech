"""Question persistence and recovery when upstream research stalls."""
import os
import threading
import unittest
from unittest.mock import patch
from uuid import uuid4

import retrieval
import test_api


class QuestionReadinessTests(unittest.IsolatedAsyncioTestCase):
    asyncSetUp = test_api.EquipmentAPITests.asyncSetUp
    request = test_api.EquipmentAPITests.request

    async def test_timeout_saves_once_and_late_research_cannot_replace_answer(self):
        release = threading.Event()
        finished = threading.Event()

        def stalled(*args):
            release.wait(2)
            finished.set()
            return [], 'LATE RESULT MUST NOT APPEAR'

        payload = dict(question='Find the Honda GX160 manual', request_key=str(uuid4()))
        with patch.dict(os.environ, GOPHERTECH_RESEARCH_NETWORK='1'), patch.object(retrieval, 'LOOKUP_TIMEOUT', .03), patch.object(retrieval, '_answer', side_effect=stalled):
            try:
                status, job = await self.request('POST', '/jobs/question', payload)
                self.assertEqual(status, 200)
                self.assertIn('timed out', job['messages'][-1]['content'])
                _, replay = await self.request('POST', '/jobs/question', payload)
                self.assertEqual(replay['id'], job['id'])
                self.assertEqual(len(replay['messages']), 2)
            finally:
                release.set()
                finished.wait(1)
        _, reopened = await self.request('GET', '/jobs/' + job['id'])
        self.assertEqual(reopened['messages'], job['messages'])
        _, next_job = await self.request('POST', '/jobs/question', dict(question='My tractor will not start', request_key=str(uuid4())))
        self.assertNotEqual(next_job['id'], job['id'])
        self.assertNotIn('model', next_job['context'])
        self.assertIn('petrol or diesel', next_job['messages'][-1]['content'])
