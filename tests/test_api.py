"""Run with .venv/bin/python -m unittest discover -s tests -v.

Exercise the ASGI app directly, with no live server or extra test dependencies.
Both database references are patched before entering the app lifespan.
"""
import os
import asyncio
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import database
import main


class EquipmentAPITests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.db = Path(self.temp.name) / 'test.db'
        self.patches = [patch.dict(os.environ, GOPHERTECH_LOCAL_AI='0', GOPHERTECH_RESEARCH_NETWORK='0'), patch.object(database, 'DATABASE', self.db),
                        patch.object(main, 'DATABASE', self.db)]
        for patcher in self.patches:
            patcher.start()
            self.addCleanup(patcher.stop)
        self.lifespan = main.app.router.lifespan_context(main.app)
        await self.lifespan.__aenter__()
        self.addAsyncCleanup(self.lifespan.__aexit__, None, None, None)

    async def request(self, method, path, payload=None):
        raw = b'' if payload is None else json.dumps(payload).encode()
        events = []
        received = False

        async def receive():
            nonlocal received
            if not received:
                received = True
                return {'type': 'http.request', 'body': raw, 'more_body': False}
            await asyncio.Future()

        async def send(event):
            events.append(event)

        scope = {'type': 'http', 'asgi': {'version': '3.0'},
                 'http_version': '1.1', 'method': method, 'scheme': 'http',
                 'path': path, 'raw_path': path.encode(), 'query_string': b'',
                 'root_path': '', 'headers': [(b'content-type', b'application/json')],
                 'server': ('test', 80), 'client': ('test', 1234)}
        await asyncio.wait_for(main.app(scope, receive, send), timeout=5)
        status = next(event['status'] for event in events if event['type'] == 'http.response.start')
        body = b''.join(event.get('body', b'') for event in events if event['type'] == 'http.response.body')
        return status, json.loads(body)

    async def test_health_and_identity(self):
        self.assertEqual(await self.request('GET', '/health'), (200, {'status': 'healthy'}))
        status, body = await self.request('GET', '/')
        self.assertEqual(status, 200)
        self.assertEqual(body['application'], 'GopherTech')

    async def test_empty_inventory(self):
        self.assertEqual(await self.request('GET', '/equipment'), (200, {'equipment': []}))

    async def test_create_and_list_all_fields(self):
        item = {'name': 'Workbench meter', 'manufacturer': 'HawkLabs',
                'model': 'M1', 'notes': 'Calibration due — bench A'}
        status, created = await self.request('POST', '/equipment', item)
        self.assertEqual(status, 201)
        status, listing = await self.request('GET', '/equipment')
        self.assertEqual(status, 200)
        self.assertEqual(listing['equipment'], [dict(item, id=created['id'])])

    async def test_optional_fields_and_id_order(self):
        ids = []
        for name in ['Second alphabetically', 'First alphabetically']:
            status, created = await self.request('POST', '/equipment', {'name': name})
            self.assertEqual(status, 201)
            ids.append(created['id'])
        _, listing = await self.request('GET', '/equipment')
        self.assertEqual([row['id'] for row in listing['equipment']], ids)
        self.assertIsNone(listing['equipment'][0]['manufacturer'])
        self.assertIsNone(listing['equipment'][0]['model'])
        self.assertIsNone(listing['equipment'][0]['notes'])

    async def test_missing_or_invalid_name_rejected_without_writes(self):
        for payload in [{}, {'name': None}, {'name': ['invalid']}]:
            status, _ = await self.request('POST', '/equipment', payload)
            self.assertEqual(status, 422)
        self.assertEqual(await self.request('GET', '/equipment'), (200, {'equipment': []}))

    async def test_sql_text_is_stored_as_data(self):
        name = "Meter'); DROP TABLE equipment; --"
        self.assertEqual((await self.request('POST', '/equipment', {'name': name}))[0], 201)
        _, listing = await self.request('GET', '/equipment')
        self.assertEqual(listing['equipment'][0]['name'], name)

    async def test_initialization_preserves_existing_records(self):
        await self.request('POST', '/equipment', {'name': 'Keep me'})
        database.initialize_database()
        _, listing = await self.request('GET', '/equipment')
        self.assertEqual(len(listing['equipment']), 1)
        self.assertEqual(listing['equipment'][0]['name'], 'Keep me')

    async def test_unknown_route(self):
        self.assertEqual((await self.request('GET', '/missing'))[0], 404)


    async def make_item(self):
        _, created = await self.request('POST', '/equipment', {'name': 'Test drill'})
        return created['id']

    async def test_checkout_and_return(self):
        equipment_id = await self.make_item()
        status, listing = await self.request('GET', '/equipment/availability')
        self.assertEqual(status, 200)
        self.assertEqual(listing['equipment'][0]['status'], 'available')
        status, loan = await self.request('POST', f'/equipment/{equipment_id}/checkout', {'borrower': '  Sam  '})
        self.assertEqual(status, 201)
        self.assertEqual(loan['borrower'], 'Sam')
        _, listing = await self.request('GET', '/equipment/availability')
        row = listing['equipment'][0]
        self.assertEqual(row['status'], 'checked_out')
        self.assertEqual(row['checkout_id'], loan['id'])
        self.assertEqual(row['borrower'], 'Sam')
        self.assertTrue(row['checked_out_at'].endswith('+00:00'))
        status, returned = await self.request('POST', f'/equipment/{equipment_id}/checkin', {'checkout_id': loan['id']})
        self.assertEqual(status, 200)
        self.assertIn('returned_at', returned)
        _, listing = await self.request('GET', '/equipment/availability')
        self.assertEqual(listing['equipment'][0]['status'], 'available')
        self.assertIsNone(listing['equipment'][0]['borrower'])
        import sqlite3
        from contextlib import closing
        with closing(sqlite3.connect(self.db)) as connection:
            history = connection.execute('SELECT borrower, returned_at FROM equipment_loans').fetchone()
        self.assertEqual(history[0], 'Sam')
        self.assertIsNotNone(history[1])

    async def test_checkout_requires_name(self):
        equipment_id = await self.make_item()
        for payload in [{}, {'borrower': ''}, {'borrower': '   '}, {'borrower': None}, {'borrower': 'x' * 121}]:
            self.assertEqual((await self.request('POST', f'/equipment/{equipment_id}/checkout', payload))[0], 422)
        _, listing = await self.request('GET', '/equipment/availability')
        self.assertEqual(listing['equipment'][0]['status'], 'available')

    async def test_missing_equipment_cannot_be_taken_or_returned(self):
        self.assertEqual((await self.request('POST', '/equipment/999/checkout', {'borrower': 'Sam'}))[0], 404)
        self.assertEqual((await self.request('POST', '/equipment/999/checkin', {'checkout_id': 1}))[0], 404)

    async def test_two_people_cannot_take_same_equipment(self):
        equipment_id = await self.make_item()
        results = await asyncio.gather(*[
            self.request('POST', f'/equipment/{equipment_id}/checkout', {'borrower': name})
            for name in ['Sam', 'Alex']
        ])
        self.assertEqual(sorted(status for status, _ in results), [201, 409])
        _, listing = await self.request('GET', '/equipment/availability')
        self.assertEqual(len(listing['equipment']), 1)
        self.assertIn(listing['equipment'][0]['borrower'], ['Sam', 'Alex'])

    async def test_stale_return_does_not_return_next_persons_loan(self):
        equipment_id = await self.make_item()
        _, first = await self.request('POST', f'/equipment/{equipment_id}/checkout', {'borrower': 'Sam'})
        payload = {'checkout_id': first['id']}
        self.assertEqual((await self.request('POST', f'/equipment/{equipment_id}/checkin', payload))[0], 200)
        self.assertEqual((await self.request('POST', f'/equipment/{equipment_id}/checkin', payload))[0], 409)
        _, second = await self.request('POST', f'/equipment/{equipment_id}/checkout', {'borrower': 'Alex'})
        self.assertEqual((await self.request('POST', f'/equipment/{equipment_id}/checkin', payload))[0], 409)
        _, listing = await self.request('GET', '/equipment/availability')
        self.assertEqual(listing['equipment'][0]['checkout_id'], second['id'])
        self.assertEqual(listing['equipment'][0]['borrower'], 'Alex')

    async def test_return_requires_matching_checkout(self):
        first_id = await self.make_item()
        second_id = await self.make_item()
        _, loan = await self.request('POST', f'/equipment/{first_id}/checkout', {'borrower': 'Sam'})
        self.assertEqual((await self.request('POST', f'/equipment/{second_id}/checkin', {'checkout_id': loan['id']}))[0], 409)
        self.assertEqual((await self.request('POST', f'/equipment/{first_id}/checkin', {}))[0], 422)
        database.initialize_database()
        _, listing = await self.request('GET', '/equipment/availability')
        self.assertEqual(listing['equipment'][0]['borrower'], 'Sam')


    async def test_upgrade_from_original_equipment_database(self):
        import sqlite3
        from contextlib import closing
        legacy = Path(self.temp.name) / 'legacy.db'
        with closing(sqlite3.connect(legacy)) as connection:
            connection.execute('CREATE TABLE equipment (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, manufacturer TEXT, model TEXT, notes TEXT)')
            connection.execute("INSERT INTO equipment(name, notes) VALUES ('Original tool', 'Keep these notes')")
            connection.commit()
        with patch.object(database, 'DATABASE', legacy), patch.object(main, 'DATABASE', legacy):
            database.initialize_database()
            database.initialize_database()
            status, listing = await self.request('GET', '/equipment/availability')
        self.assertEqual(status, 200)
        self.assertEqual(len(listing['equipment']), 1)
        self.assertEqual(listing['equipment'][0]['name'], 'Original tool')
        self.assertEqual(listing['equipment'][0]['notes'], 'Keep these notes')
        self.assertEqual(listing['equipment'][0]['status'], 'available')

if __name__ == '__main__':
    unittest.main()
