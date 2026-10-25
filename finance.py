"""Local payable/receivable tracking; all stored money is integer cents."""
from contextlib import closing
from datetime import date, datetime, timezone
from decimal import Decimal
import hashlib
import json
import sqlite3
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, field_validator, model_validator
import database

router = APIRouter(prefix='/finance', tags=['Bills and invoices'])
Money = Annotated[Decimal, Field(gt=0, max_digits=12, decimal_places=2, allow_inf_nan=False)]


def initialize_finance(connection):
    connection.execute('''CREATE TABLE IF NOT EXISTS finance_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL CHECK(kind IN ('payable', 'receivable')),
        party TEXT NOT NULL COLLATE NOCASE,
        reference TEXT NOT NULL COLLATE NOCASE,
        issue_date TEXT NOT NULL,
        due_date TEXT NOT NULL CHECK(due_date >= issue_date),
        currency TEXT NOT NULL CHECK(currency IN ('CAD','USD','EUR','GBP')),
        amount_cents INTEGER NOT NULL CHECK(typeof(amount_cents) = 'integer' AND amount_cents > 0),
        notes TEXT NOT NULL DEFAULT '',
        request_key TEXT NOT NULL UNIQUE,
        request_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(kind, party, reference, currency)
    )''')
    connection.execute('''CREATE TABLE IF NOT EXISTS finance_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL REFERENCES finance_documents(id),
        amount_cents INTEGER NOT NULL CHECK(typeof(amount_cents) = 'integer' AND amount_cents > 0),
        paid_on TEXT NOT NULL,
        reference TEXT NOT NULL DEFAULT '',
        request_key TEXT NOT NULL UNIQUE,
        request_hash TEXT NOT NULL,
        created_at TEXT NOT NULL
    )''')
    connection.execute('CREATE INDEX IF NOT EXISTS finance_payments_document ON finance_payments(document_id)')


class DocumentCreate(BaseModel):
    kind: Literal['payable', 'receivable']
    party: str = Field(min_length=1, max_length=160)
    reference: str = Field(min_length=1, max_length=120)
    issue_date: date
    due_date: date
    currency: Literal['CAD', 'USD', 'EUR', 'GBP']
    amount: Money
    notes: str = Field(default='', max_length=2000)
    request_key: UUID

    @field_validator('party', 'reference', mode='before')
    @classmethod
    def trim_required(cls, value):
        return value.strip() if isinstance(value, str) else value

    @model_validator(mode='after')
    def ordered_dates(self):
        if self.due_date < self.issue_date:
            raise ValueError('Due date must be on or after the bill or invoice date.')
        return self


class PaymentCreate(BaseModel):
    amount: Money
    paid_on: date
    reference: str = Field(default='', max_length=120)
    request_key: UUID

    @model_validator(mode='after')
    def no_future_payment(self):
        if self.paid_on > date.today():
            raise ValueError('Record payments only after they have happened.')
        return self


def money(cents):
    return f'{cents // 100}.{cents % 100:02d}'


def fingerprint(values):
    return hashlib.sha256(json.dumps(values, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def connect():
    connection = sqlite3.connect(database.DATABASE, timeout=10)
    connection.row_factory = sqlite3.Row
    connection.execute('PRAGMA foreign_keys = ON')
    return connection


SELECT_DOCUMENTS = '''SELECT d.*, COALESCE(SUM(p.amount_cents), 0) AS paid_cents
    FROM finance_documents d LEFT JOIN finance_payments p ON p.document_id = d.id'''


def present(row, today):
    result = dict(row)
    result.pop('request_key', None)
    result.pop('request_hash', None)
    balance = result['amount_cents'] - result['paid_cents']
    result.update(amount=money(result['amount_cents']), paid=money(result['paid_cents']),
                  balance=money(balance), balance_cents=balance,
                  status='paid' if balance == 0 else ('partial' if result['paid_cents'] else 'unpaid'),
                  overdue=balance > 0 and result['due_date'] < today.isoformat())
    return result


def get_document(connection, document_id):
    row = connection.execute(SELECT_DOCUMENTS + ' WHERE d.id = ? GROUP BY d.id', (document_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail='That bill or invoice was not found.')
    document = present(row, date.today())
    document['payments'] = [dict(id=p['id'], amount=money(p['amount_cents']), amount_cents=p['amount_cents'],
                                 paid_on=p['paid_on'], reference=p['reference'])
                            for p in connection.execute('SELECT * FROM finance_payments WHERE document_id = ? ORDER BY paid_on, id', (document_id,))]
    return document


@router.get('/documents')
def list_documents():
    today = date.today()
    with closing(connect()) as connection:
        rows = connection.execute(SELECT_DOCUMENTS + ' GROUP BY d.id ORDER BY d.due_date, d.id').fetchall()
    documents = [present(row, today) for row in rows]
    totals = {}
    for row in documents:
        key = (row['kind'], row['currency'])
        total = totals.setdefault(key, dict(kind=key[0], currency=key[1], outstanding_cents=0, overdue_cents=0, open_count=0))
        total['outstanding_cents'] += row['balance_cents']
        total['overdue_cents'] += row['balance_cents'] if row['overdue'] else 0
        total['open_count'] += int(row['balance_cents'] > 0)
    for total in totals.values():
        total.update(outstanding=money(total['outstanding_cents']), overdue=money(total['overdue_cents']))
    return dict(documents=documents, totals=list(totals.values()), as_of=today.isoformat())


@router.get('/documents/{document_id}')
def document_details(document_id: int):
    with closing(connect()) as connection:
        connection.execute('BEGIN')
        return get_document(connection, document_id)


@router.post('/documents', status_code=201)
def create_document(item: DocumentCreate):
    values = dict(kind=item.kind, party=item.party, reference=item.reference,
                  issue_date=item.issue_date.isoformat(), due_date=item.due_date.isoformat(),
                  currency=item.currency, amount_cents=int(item.amount * 100), notes=item.notes.strip())
    digest = fingerprint(values)
    with closing(connect()) as connection:
        with connection:
            connection.execute('BEGIN IMMEDIATE')
            existing = connection.execute('SELECT id, request_hash FROM finance_documents WHERE request_key = ?', (str(item.request_key),)).fetchone()
            if existing:
                if existing['request_hash'] != digest:
                    raise HTTPException(status_code=409, detail='This save was already used for different details. Refresh before starting another record.')
                return get_document(connection, existing['id'])
            try:
                cursor = connection.execute('''INSERT INTO finance_documents
                    (kind, party, reference, issue_date, due_date, currency, amount_cents, notes, request_key, request_hash, created_at)
                    VALUES (:kind, :party, :reference, :issue_date, :due_date, :currency, :amount_cents, :notes, :request_key, :request_hash, :created_at)''',
                    dict(values, request_key=str(item.request_key), request_hash=digest,
                         created_at=datetime.now(timezone.utc).isoformat(timespec='seconds')))
            except sqlite3.IntegrityError:
                raise HTTPException(status_code=409, detail='That bill or invoice number already exists for this supplier or customer and currency.') from None
            return get_document(connection, cursor.lastrowid)


@router.post('/documents/{document_id}/payments', status_code=201)
def record_payment(document_id: int, item: PaymentCreate):
    values = dict(document_id=document_id, amount_cents=int(item.amount * 100),
                  paid_on=item.paid_on.isoformat(), reference=item.reference.strip())
    digest = fingerprint(values)
    with closing(connect()) as connection:
        with connection:
            connection.execute('BEGIN IMMEDIATE')
            document = get_document(connection, document_id)
            existing = connection.execute('SELECT request_hash FROM finance_payments WHERE request_key = ?', (str(item.request_key),)).fetchone()
            if existing:
                if existing['request_hash'] != digest:
                    raise HTTPException(status_code=409, detail='This payment save was already used for different details. Refresh before recording another payment.')
                return document
            if item.paid_on.isoformat() < document['issue_date']:
                raise HTTPException(status_code=422, detail='Payment date cannot be before the bill or invoice date.')
            if values['amount_cents'] > document['balance_cents']:
                raise HTTPException(status_code=409, detail='This payment is more than the remaining balance. Refresh and check the amount.')
            connection.execute('''INSERT INTO finance_payments
                (document_id, amount_cents, paid_on, reference, request_key, request_hash, created_at)
                VALUES (:document_id, :amount_cents, :paid_on, :reference, :request_key, :request_hash, :created_at)''',
                dict(values, request_key=str(item.request_key), request_hash=digest,
                     created_at=datetime.now(timezone.utc).isoformat(timespec='seconds')))
            return get_document(connection, document_id)
