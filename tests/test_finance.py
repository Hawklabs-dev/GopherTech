from datetime import date, timedelta
from uuid import uuid4
import asyncio
import sqlite3
from contextlib import closing
import unittest
import test_api
import database


class FinanceTests(unittest.IsolatedAsyncioTestCase):
    asyncSetUp = test_api.EquipmentAPITests.asyncSetUp
    request = test_api.EquipmentAPITests.request
    make_item = test_api.EquipmentAPITests.make_item

    def document(self, **updates):
        today = date.today()
        data = dict(kind='payable', party='Workshop Supply', reference='BILL-01',
                    issue_date=(today - timedelta(days=30)).isoformat(),
                    due_date=(today - timedelta(days=1)).isoformat(), currency='CAD',
                    amount='100.10', notes='Parts', request_key=str(uuid4()))
        return dict(data, **updates)

    def payment(self, amount='10.00', **updates):
        return dict(dict(amount=amount, paid_on=date.today().isoformat(),
                         reference='Transfer recorded', request_key=str(uuid4())), **updates)

    async def create(self, **updates):
        status, row = await self.request('POST', '/finance/documents', self.document(**updates))
        self.assertEqual(status, 201, row)
        return row

    async def test_finance_empty(self):
        status, body = await self.request('GET', '/finance/documents')
        self.assertEqual(status, 200)
        self.assertEqual(body['documents'], [])
        self.assertEqual(body['totals'], [])

    async def test_bills_invoices_and_currency_totals(self):
        await self.create()
        await self.create(kind='receivable', amount='200.20')
        await self.create(currency='USD', amount='3.05')
        _, body = await self.request('GET', '/finance/documents')
        totals = {(t['kind'], t['currency']): t for t in body['totals']}
        self.assertEqual(totals['payable', 'CAD']['outstanding'], '100.10')
        self.assertEqual(totals['receivable', 'CAD']['outstanding'], '200.20')
        self.assertEqual(totals['payable', 'USD']['outstanding'], '3.05')
        self.assertEqual(totals['payable', 'CAD']['overdue'], '100.10')

    async def test_partial_and_full_payments_and_history(self):
        row = await self.create(amount='0.30')
        url = f"/finance/documents/{row['id']}/payments"
        status, partial = await self.request('POST', url, self.payment('0.10'))
        self.assertEqual(status, 201)
        self.assertEqual((partial['paid'], partial['balance'], partial['status']), ('0.10', '0.20', 'partial'))
        status, paid = await self.request('POST', url, self.payment('0.20'))
        self.assertEqual(status, 201)
        self.assertEqual((paid['paid'], paid['balance'], paid['status'], paid['overdue']), ('0.30', '0.00', 'paid', False))
        self.assertEqual(len(paid['payments']), 2)
        _, history = await self.request('GET', f"/finance/documents/{row['id']}")
        self.assertEqual(len(history['payments']), 2)
        _, body = await self.request('GET', '/finance/documents')
        self.assertEqual(body['totals'][0]['open_count'], 0)
        self.assertEqual(body['totals'][0]['outstanding'], '0.00')

    async def test_document_retry_and_duplicate_reference(self):
        payload = self.document()
        first_status, first = await self.request('POST', '/finance/documents', payload)
        second_status, second = await self.request('POST', '/finance/documents', payload)
        self.assertEqual((first_status, second_status), (201, 201))
        self.assertEqual(first['id'], second['id'])
        self.assertEqual((await self.request('POST', '/finance/documents', dict(payload, amount='1.00')))[0], 409)
        self.assertEqual((await self.request('POST', '/finance/documents', dict(payload, request_key=str(uuid4()), party='workshop supply', reference='bill-01')))[0], 409)
        _, body = await self.request('GET', '/finance/documents')
        self.assertEqual(len(body['documents']), 1)

    async def test_payment_retry_and_payload_conflict(self):
        row = await self.create()
        payload = self.payment()
        url = f"/finance/documents/{row['id']}/payments"
        await self.request('POST', url, payload)
        status, retried = await self.request('POST', url, payload)
        self.assertEqual(status, 201)
        self.assertEqual(retried['paid'], '10.00')
        self.assertEqual(len(retried['payments']), 1)
        self.assertEqual((await self.request('POST', url, dict(payload, amount='20.00')))[0], 409)

    async def test_overpayment_and_simultaneous_payments(self):
        row = await self.create(amount='100.00')
        url = f"/finance/documents/{row['id']}/payments"
        self.assertEqual((await self.request('POST', url, self.payment('100.01')))[0], 409)
        results = await asyncio.gather(*[self.request('POST', url, self.payment('75.00')) for _ in range(2)])
        self.assertEqual(sorted(status for status, _ in results), [201, 409])
        _, detail = await self.request('GET', f"/finance/documents/{row['id']}")
        self.assertEqual(detail['balance'], '25.00')

    async def test_validation_and_missing_records(self):
        for changes in [dict(party='  '), dict(reference=''), dict(amount='0'), dict(amount='-1'),
                        dict(amount='1.001'), dict(amount='NaN'), dict(amount='Infinity'),
                        dict(amount='10000000000.00'), dict(currency='ZZZ'), dict(kind='other'),
                        dict(due_date='not a date'), dict(due_date='2000-01-01')]:
            status, _ = await self.request('POST', '/finance/documents', self.document(**changes))
            self.assertEqual(status, 422, changes)
        self.assertEqual((await self.request('GET', '/finance/documents/999'))[0], 404)
        self.assertEqual((await self.request('POST', '/finance/documents/999/payments', self.payment()))[0], 404)
        row = await self.create()
        url = f"/finance/documents/{row['id']}/payments"
        for payload in [self.payment('0'), self.payment('-1'), self.payment('0.001'),
                        self.payment(paid_on=(date.today()+timedelta(days=1)).isoformat()),
                        self.payment(paid_on='2000-01-01')]:
            self.assertEqual((await self.request('POST', url, payload))[0], 422)

    async def test_due_today_not_overdue_and_text_is_data(self):
        row = await self.create(due_date=date.today().isoformat(), party="Supplier'); DROP TABLE equipment; --")
        self.assertFalse(row['overdue'])
        self.assertEqual((await self.request('GET', '/equipment'))[0], 200)

    async def test_reinitialization_preserves_finance_and_equipment(self):
        await self.make_item()
        row = await self.create()
        await self.request('POST', f"/finance/documents/{row['id']}/payments", self.payment())
        database.initialize_database()
        database.initialize_database()
        _, detail = await self.request('GET', f"/finance/documents/{row['id']}")
        self.assertEqual(detail['paid'], '10.00')
        with closing(sqlite3.connect(self.db)) as connection:
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM equipment').fetchone()[0], 1)
