"""Work order identity, safe migration and persistence against disposable SQLite."""
from uuid import uuid4
import sqlite3
import unittest
import database
import jobs
import test_api


class WorkOrderTests(unittest.IsolatedAsyncioTestCase):
    asyncSetUp = test_api.EquipmentAPITests.asyncSetUp
    request = test_api.EquipmentAPITests.request

    async def test_number_validation_uniqueness_and_creation_retry(self):
        payload = dict(request_key=str(uuid4()), work_order_number='  SHOP-102  ', machine_description='  Honda GX160  ')
        code, first = await self.request('POST', '/jobs', payload)
        self.assertEqual(code, 201)
        self.assertEqual(first['work_order_number'], 'SHOP-102')
        self.assertEqual(first['machine_description'], 'Honda GX160')
        _, replay = await self.request('POST', '/jobs', payload)
        self.assertEqual(replay['id'], first['id'])
        code, _ = await self.request('POST', '/jobs', dict(payload, request_key=str(uuid4()), work_order_number='shop-102'))
        self.assertEqual(code, 409)
        code, _ = await self.request('POST', '/jobs', dict(payload, machine_description='Different machine'))
        self.assertEqual(code, 409)
        for number in ('   ', 'x' * 81):
            code, _ = await self.request('POST', '/jobs', dict(request_key=str(uuid4()), work_order_number=number))
            self.assertEqual(code, 422)
        _, listing = await self.request('GET', '/jobs')
        self.assertEqual(len(listing['jobs']), 1)

    async def test_auto_numbers_and_machine_notes_parts_remain_separate(self):
        orders = []
        for _ in range(2):
            code, job = await self.request('POST', '/jobs', dict(request_key=str(uuid4())))
            self.assertEqual(code, 201)
            self.assertTrue(job['work_order_number'].startswith('WO-'))
            orders.append(job)
        self.assertNotEqual(orders[0]['work_order_number'], orders[1]['work_order_number'])
        url = '/jobs/' + orders[0]['id']
        code, _ = await self.request('PUT', url + '/state', dict(machine_description='2004 Honda ATV', notes='Measured 12 V', parts=['Fuse']))
        self.assertEqual(code, 200)
        database.initialize_database()
        _, reopened = await self.request('GET', url)
        self.assertEqual(reopened['machine_description'], '2004 Honda ATV')
        self.assertEqual(reopened['notes'], 'Measured 12 V')
        self.assertEqual(reopened['parts'], ['Fuse'])
        _, other = await self.request('GET', '/jobs/' + orders[1]['id'])
        self.assertEqual((other['machine_description'], other['notes'], other['parts']), ('', '', []))
        _, listing = await self.request('GET', '/jobs')
        self.assertEqual({row['work_order_number'] for row in listing['jobs']}, {o['work_order_number'] for o in orders})

    async def test_legacy_migration_preserves_content_and_is_repeatable(self):
        # Recreate the old schema in this test's disposable database only.
        with sqlite3.connect(self.db) as c:
            c.execute('DROP TABLE workshop_sources')
            c.execute('DROP TABLE workshop_messages')
            c.execute('DROP TABLE workshop_jobs')
            c.execute("CREATE TABLE workshop_jobs (id TEXT PRIMARY KEY,title TEXT NOT NULL,context TEXT NOT NULL DEFAULT '{}',notes TEXT NOT NULL DEFAULT '',parts TEXT NOT NULL DEFAULT '[]',created_at TEXT NOT NULL,updated_at TEXT NOT NULL,creation_key TEXT UNIQUE)")
            c.execute("INSERT INTO workshop_jobs VALUES(?,?,'{}',?,'[]',?,?,NULL)", ('legacy-job', 'Old repair', 'Keep these measurements', '2026-01-01', '2026-01-01'))
            jobs.initialize_jobs(c)
            before = c.execute('SELECT * FROM workshop_jobs').fetchone()
            jobs.initialize_jobs(c)
            self.assertEqual(c.execute('SELECT * FROM workshop_jobs').fetchone(), before)
            self.assertEqual(c.execute('SELECT title,notes,work_order_number FROM workshop_jobs').fetchone(), ('Old repair', 'Keep these measurements', 'WO-legacy-job'))
            self.assertEqual(c.execute('PRAGMA integrity_check').fetchone()[0], 'ok')

    async def test_sections_save_independently_and_survive_initialization(self):
        _, first = await self.request('POST', '/jobs', dict(request_key=str(uuid4())))
        _, second = await self.request('POST', '/jobs', dict(request_key=str(uuid4())))
        sections = {'parts': {'task': 'Brake pads', 'notes': 'Measure old pads'},
                    'repair': {'task': 'Replace lines', 'notes': 'Repair notes'},
                    'fabricate': {'task': '', 'notes': ''}}
        code, saved = await self.request('PUT', '/jobs/' + first['id'] + '/state', dict(section_drafts=sections))
        self.assertEqual(code, 200)
        self.assertEqual(saved['section_drafts'], sections)
        self.assertEqual(saved['notes'], 'Measure old pads')
        database.initialize_database()
        _, reopened = await self.request('GET', '/jobs/' + first['id'])
        self.assertEqual(reopened['section_drafts'], sections)
        _, other = await self.request('GET', '/jobs/' + second['id'])
        self.assertEqual(other['section_drafts'], {})

    async def test_section_validation_rejects_unknown_or_oversized_values(self):
        _, job = await self.request('POST', '/jobs', dict(request_key=str(uuid4())))
        for sections in ({'unknown': {'task': 'x'}}, {'parts': {'task': 'x' * 301}}, {'repair': {'notes': 'x' * 20001}}):
            code, _ = await self.request('PUT', '/jobs/' + job['id'] + '/state', dict(section_drafts=sections))
            self.assertEqual(code, 422)
        _, unchanged = await self.request('GET', '/jobs/' + job['id'])
        self.assertEqual(unchanged['section_drafts'], {})

    async def test_legacy_notes_updates_preserve_other_section_notes(self):
        _, job = await self.request('POST', '/jobs', dict(request_key=str(uuid4())))
        url = '/jobs/' + job['id'] + '/state'
        await self.request('PUT', url, dict(section_drafts={'parts': {'task':'Pads', 'notes':'Old'}, 'repair': {'task':'Lines', 'notes':'Keep repair notes'}}))
        code, saved = await self.request('PUT', url, dict(notes='Updated legacy notes'))
        self.assertEqual(code, 200)
        self.assertEqual(saved['section_drafts']['parts']['notes'], 'Updated legacy notes')
        self.assertEqual(saved['section_drafts']['repair']['notes'], 'Keep repair notes')
