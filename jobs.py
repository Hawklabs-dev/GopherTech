"""Persistent workshop conversations in explicit reference mode; no AI/API provider."""
from contextlib import closing
from datetime import datetime, timezone
import json
import re
import sqlite3
from uuid import UUID, uuid4
from urllib.parse import urlsplit

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, field_validator
import database
import research
import knowledge
import answering
import search_providers
import retrieval
import local_ai

router = APIRouter(prefix='/jobs', tags=['Workshop jobs'])
MODE = 'Reference mode — guided rules, not AI'
STARTING_GUIDE = 'https://www.briggsandstratton.com/en-us/support/faqs/engine-problem-solving-tips'


def initialize_jobs(connection):
    connection.execute('''CREATE TABLE IF NOT EXISTS workshop_jobs (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, context TEXT NOT NULL DEFAULT '{}',
        notes TEXT NOT NULL DEFAULT '', parts TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        creation_key TEXT UNIQUE)''')
    connection.execute('''CREATE TABLE IF NOT EXISTS workshop_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT, job_id TEXT NOT NULL REFERENCES workshop_jobs(id),
        role TEXT NOT NULL CHECK(role IN ('user','assistant')), content TEXT NOT NULL,
        created_at TEXT NOT NULL, request_key TEXT UNIQUE, request_question TEXT)''')
    connection.execute('''CREATE TABLE IF NOT EXISTS workshop_sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT, job_id TEXT NOT NULL REFERENCES workshop_jobs(id),
        url TEXT NOT NULL, title TEXT NOT NULL, document TEXT,
        updated_at TEXT NOT NULL, UNIQUE(job_id, url))''')
    connection.execute('CREATE INDEX IF NOT EXISTS workshop_messages_job ON workshop_messages(job_id, id)')


def connect():
    c = sqlite3.connect(database.DATABASE, timeout=10)
    c.row_factory = sqlite3.Row
    c.execute('PRAGMA foreign_keys = ON')
    return c


def now():
    return datetime.now(timezone.utc).isoformat(timespec='microseconds')


class JobCreate(BaseModel):
    title: str = Field(default='Workshop job', min_length=1, max_length=160)
    request_key: UUID


class Question(BaseModel):
    question: str = Field(min_length=1, max_length=4000)
    job_id: UUID | None = None
    request_key: UUID

    @field_validator('question', mode='before')
    @classmethod
    def trim_question(cls, value):
        return value.strip() if isinstance(value, str) else value


class JobState(BaseModel):
    notes: str | None = Field(default=None, max_length=20000)
    parts: list[str] | None = Field(default=None, max_length=100)

    @field_validator('parts')
    @classmethod
    def bounded_parts(cls, value):
        if value is not None and any(not item.strip() or len(item) > 4000 for item in value):
            raise ValueError('Each part needs a description of 1–4000 characters.')
        return value


def get_job(c, job_id):
    row = c.execute('SELECT * FROM workshop_jobs WHERE id = ?', (str(job_id),)).fetchone()
    if row is None:
        raise HTTPException(404, 'This saved job was not found.')
    job = dict(row)
    job.pop('creation_key', None)
    job['context'] = json.loads(job['context'])
    job['parts'] = json.loads(job['parts'])
    job['messages'] = [dict(item) for item in c.execute('SELECT id, role, content, created_at FROM workshop_messages WHERE job_id=? ORDER BY id', (str(job_id),))]
    job['sources'] = [dict(item) for item in c.execute('SELECT id, url, title, document IS NOT NULL AS read, updated_at FROM workshop_sources WHERE job_id=? ORDER BY id DESC', (str(job_id),))]
    ranks = {entry['url']: index for index, entry in enumerate(matching_sources(job['context']))}
    job['sources'].sort(key=lambda entry: (0 if entry['read'] else 1, ranks.get(entry['url'], 100), entry['id']))
    job.update(mode=MODE, ai_enabled=False)
    job['research'] = dict(local_checked=True, **json.loads(job['context'].pop('_research', '{}')))
    return job


def insert_job(c, title, creation_key=None):
    job_id, timestamp = str(uuid4()), now()
    c.execute('INSERT INTO workshop_jobs(id,title,created_at,updated_at,creation_key) VALUES(?,?,?,?,?)',
              (job_id, title[:160], timestamp, timestamp, creation_key))
    return job_id


@router.get('')
def list_jobs():
    with closing(connect()) as c:
        rows = c.execute('SELECT id,title,created_at,updated_at FROM workshop_jobs ORDER BY updated_at DESC,id').fetchall()
    return dict(jobs=[dict(row) for row in rows], mode=MODE)


@router.post('', status_code=201)
def create_job(item: JobCreate):
    with closing(connect()) as c, c:
        c.execute('BEGIN IMMEDIATE')
        row = c.execute('SELECT id FROM workshop_jobs WHERE creation_key=?', (str(item.request_key),)).fetchone()
        return get_job(c, row['id'] if row else insert_job(c, item.title, str(item.request_key)))


@router.get('/{job_id}')
def job_details(job_id: UUID):
    with closing(connect()) as c:
        return get_job(c, job_id)


@router.put('/{job_id}/state')
def save_state(job_id: UUID, item: JobState):
    with closing(connect()) as c, c:
        c.execute('BEGIN IMMEDIATE')
        get_job(c, job_id)
        if item.notes is not None:
            c.execute('UPDATE workshop_jobs SET notes=? WHERE id=?', (item.notes, str(job_id)))
        if item.parts is not None:
            c.execute('UPDATE workshop_jobs SET parts=? WHERE id=?', (json.dumps(item.parts), str(job_id)))
        c.execute('UPDATE workshop_jobs SET updated_at=? WHERE id=?', (now(), str(job_id)))
        return get_job(c, job_id)


def route_question(previous, question):
    context = dict(previous)
    lower = question.lower().replace('’', "'")
    lower = re.sub(r'\b(?:john\s+deer|jd)\b', 'john deere', lower)
    lower = re.sub(r'\bhond[ae]\b', 'honda', lower)
    lower = re.sub(r'\b(?:b&s|briggs and stratton)\b', 'briggs', lower)
    if re.search(r'\b(?:other|another|different|second|third)\s+(?:riding\s+)?(?:mower|tractor|engine|machine)\b', lower):
        context = {}
    if any(term in lower for term in ('walk me through', 'step by step', 'never done', 'beginner')):
        context['response_style'] = 'guided'
    elif any(term in lower for term in ('quick answer', 'short answer', 'keep it short')):
        context['response_style'] = 'quick'
    elif any(term in lower for term in ('technical version', 'more detail', 'explain that')):
        context['response_style'] = 'detailed'
    if 'turf ranger' in lower or 'turfranger' in lower:
        if context.get('model') != 'Turf Ranger':
            context = {}
        context.update(model='Turf Ranger')
        if 'exmark' in lower: context['brand'] = 'Exmark'
    deere_model = re.search(r'\b[dxes]\d{3}\b', lower)
    model = re.search(r'\b(?:igx|igxv|gxv|gx|gcv|gc|gsv|gs|gxh|gxr)\s*-?\s*\d{2,3}\b', lower)
    if model:
        value = re.sub(r'[\s-]', '', model.group()).upper()
        if context.get('model') != value:
            for key in ('serial', 'year', 'fuel', 'fuel_observation', 'symptom', 'research_question'):
                context.pop(key, None)
        context.update(brand='Honda', model=value)
    else:
        for token, brand in [('honda', 'Honda'), ('briggs', 'Briggs & Stratton'), ('vanguard', 'Vanguard'), ('kawasaki', 'Kawasaki'), ('kohler', 'Kohler'), ('john deere', 'John Deere'), ('kubota', 'Kubota'), ('exmark', 'Exmark')]:
            if token in lower:
                if context.get('brand') not in (None, brand):
                    for key in ('model', 'serial', 'year', 'fuel', 'fuel_observation', 'symptom', 'research_question'):
                        context.pop(key, None)
                context['brand'] = brand
                break
        explicit = re.search(r'\bmodel\s*(?:is\s+)?[:#]?\s*([a-z0-9][a-z0-9-]{2,30})\b', lower)
        if deere_model and context.get('brand') == 'John Deere':
            explicit = deere_model

        if explicit:
            identified_model = (explicit.group() if explicit is deere_model else explicit.group(1)).upper()
            if context.get('model') != identified_model:
                for key in ('serial', 'year', 'fuel', 'fuel_observation', 'symptom', 'research_question'):
                    context.pop(key, None)
            context['model'] = identified_model
    for name, pattern in [('serial', r'\b(?:serial(?:\s+(?:number|prefix))?|prefix)\s*[:#]?\s*([a-z0-9][a-z0-9-]{2,40})'), ('year', r'\b(?:19|20)\d{2}\b')]:
        found = re.search(pattern, lower)
        if found:
            context[name] = (found.group(1) if name == 'serial' else found.group()).upper()
    if context.get('brand') == 'Honda':
        raw_prefix = re.search(r'\bgc[a-z]{2,5}(?:[-\s]?\d{5,10})?\b', lower)
        if raw_prefix:
            context['serial'] = raw_prefix.group().upper()
        elif re.fullmatch(r'\d{7}', lower.strip()) and re.fullmatch(r'GC[A-Z]{2,5}', context.get('serial', '')):
            context['serial'] += '-' + lower.strip()
    for value, pattern in [('Canada', r'\b(?:canada|canadian|ontario)\b'), ('US', r'\b(?:united states|usa|u\.s\.)\b'), ('UK', r'\b(?:united kingdom|uk|britain)\b')]:
        if re.search(pattern, lower):
            context['region'] = value
    if 'diesel' in lower:
        context['fuel'] = 'diesel'
    elif any(word in lower for word in ('petrol', 'gasoline', 'gas engine')):
        context['fuel'] = 'petrol'
    if any(word in lower for word in ('fresh fuel', 'new fuel', 'tank full', 'fuel present')):
        context['fuel_observation'] = question
    if any(word in lower for word in ('wiring', 'hydraulic', 'diagram', 'manual', 'maintenance', 'service procedure', 'diagnostic procedure', 'exploded', 'parts view', 'parts list')):
        context['intent'] = 'manual'
        context['document_kind'] = next((word for word in ['wiring', 'hydraulic', 'exploded', 'parts list', 'parts view', 'diagnostic', 'service', 'maintenance'] if word in lower), 'owner')
    elif any(word in lower for word in ('replacement part', 'identify', 'part number', 'find a part', 'parts list')):
        context['intent'] = 'parts'
    elif any(word in lower for word in ('fabricat', 'weld', 'make a bracket', 'build a bracket')):
        context['intent'] = 'fabrication'
    elif any(word in lower for word in ("won't start", 'will not start', 'not start', 'turns over', 'no start', 'runs rough', 'running rough', 'stalls', 'smoke', 'cranks', 'not starting', "doesn't start", 'wont start')):
        context['intent'] = 'troubleshoot'
        context['symptom'] = question
    elif any(word in lower for word in ('torque', 'clearance', 'specification', 'specs', 'spark plug gap')):
        context['intent'] = 'specification'
    if any(word in lower for word in ('oil drain', 'drain plug', 'oil change')):
        context.update(intent='manual', document_kind='oil drain procedure')
    context.setdefault('intent', 'general')
    if any(term in lower for term in ('manual', 'diagram', 'oil drain', 'drain plug', 'oil change', 'torque', 'specs', 'specification', 'spark plug gap', 'won\'t start', 'wont start', 'not start', 'runs rough', 'running rough', 'stalls', 'replacement', 'fabricat')):
        context['task_question'] = question
    context['last_question'] = question
    return context


def matching_sources(context):
    brand = context.get('brand', '')
    if brand not in ('Honda', 'Briggs & Stratton', 'Vanguard'):
        return []
    entries = research.sources(research.SourceQuery(query=brand + ' ' + context.get('model', '')))['sources']
    if brand == 'Honda':
        entries = [entry for entry in entries if entry['brand'] == 'Honda']
        for entry in entries:
            if entry.get('kind') == 'Model lookup':
                entry['title'] += ' (US library; verify region)'
        if context.get('region') == 'Canada':
            entries.sort(key=lambda entry: 0 if entry.get('kind') == 'Model lookup' else 1 if 'Canada' in entry['title'] else 2)
    else:
        entries = [entry for entry in entries if ('Briggs' in entry['brand'] if brand == 'Briggs & Stratton' else 'Vanguard' in entry['brand'])]
    if context.get('intent') == 'troubleshoot' and brand in ('Briggs & Stratton', 'Vanguard'):
        entries.insert(0, dict(url=STARTING_GUIDE, title='Briggs & Stratton — general starting / running checks', kind='General guide, not model-specific'))
    elif context.get('intent') == 'troubleshoot' and context.get('fuel') == 'petrol':
        entries.append(dict(url=STARTING_GUIDE, title='General petrol starting guidance (Briggs; not Honda specifications)', kind='General guide, not model-specific'))
    return entries[:4]


def reference_reply(context, question):
    intent = context['intent']
    identity = ' '.join(context.get(key, '') for key in ('brand', 'model')).strip()
    lead = ('Keeping ' + identity + ' with this job.\n\n') if identity else ''
    followup = 'What is the engine make/model, and is it petrol or diesel?' if not context.get('model') else 'What is the serial prefix/range and country or region?' if not context.get('serial') and not context.get('region') else 'What is the serial prefix/range?' if not context.get('serial') else 'What country or region is it from?' if not context.get('region') else 'Which document or task do you need next?'
    if intent == 'troubleshoot':
        if context.get('fuel') == 'diesel':
            reply = 'Identify the exact engine and its starting procedure before testing the fuel system.\n\nPossible causes are not established. Petrol spark checks do not apply to diesel. Do not loosen high-pressure fuel lines or bypass interlocks.\n\nNext check: record whether cranking is normal or unusually slow, without repeated starting attempts; that observation helps choose the correct service-manual branch.'
        elif context.get('fuel') == 'petrol':
            reply = 'Start with a basic fuel-level and fuel-age check, with the engine off and cool.\n\nDocumented general guidance: fuel condition is one of the items in the manufacturer starting checklist. An empty tank is a finding; fuel present does not prove delivery is working.\n\nPossible causes include fuel delivery, ignition or compression issues; none is confirmed. Do not replace parts on that basis alone.\n\nKeep ignition sources away from fuel, follow the engine manual, and do not bypass guards or interlocks.'
            if context.get('fuel_observation'):
                reply = 'Your fuel observation is saved. Fuel present or recently added does not establish that it reaches the engine correctly.\n\nNext check: use the exact model manual to compare the normal starting controls with their observed positions. If a control differs from that procedure, record it; if it agrees, the cause is still unknown.\n\nFuel delivery, ignition and compression remain possibilities, not diagnosed faults. Keep the machine secured, engine cool and ignition sources away from fuel; do not bypass safety interlocks.'
        else:
            reply = 'First confirm what engine is fitted and whether it uses petrol or diesel.\n\nKnown: you reported a starting/running problem. Unknown: its cause. A petrol ignition checklist could be wrong for a diesel.\n\nNext useful check: with the machine secured, engine stopped and cool, read the engine identification plate and record the starting behavior you observed. That tells us which manufacturer procedure to use; it does not diagnose a faulty part.'
        if not context.get('model') or not context.get('fuel'):
            reply += '\n\n' + followup
        else:
            reply += '\n\nWhat differed from the manual starting procedure?' if context.get('fuel_observation') else '\n\nWhat did you observe about fuel level/age and cranking speed?' if context['fuel'] == 'petrol' else '\n\nWas cranking normal or unusually slow?'
        if any(term in question.lower() for term in ('more detail', 'explain', 'expand')):
            reply += '\n\nRecord one observation at a time. Stop if you see leaks, damaged wiring or an unsafe condition. A model-specific service procedure is needed before intrusive fuel, electrical or compression tests; this prototype cannot verify a diagnosis.'
    elif intent == 'manual':
        kind = context.get('document_kind', 'owner')
        reply = ('I can show manufacturer reference locations for ' + identity + '.' if matching_sources(context) else 'I do not have a matching manufacturer source in this prototype yet.')
        reply += '\n\nNo matching ' + kind + ' document has been verified. Open a source below to read it here. Compare model, serial range, year and region before choosing a document; an owner manual may not include service, wiring or hydraulic diagrams.'
        reply += '\n\n' + ('Which engine model is it, and what country is it from?' if not context.get('model') else followup)
    elif intent == 'parts':
        reply = 'Start with the machine/engine identity and the markings on the old part.\n\nI can keep the details and locate supported manufacturer parts-list sources. I cannot verify a replacement or compatibility from this description alone.\n\nWhat is the engine/machine model, and what markings or part number can you read?'
    elif intent == 'fabrication':
        reply = 'Start by recording the mating dimensions and what the part must do.\n\nI can keep a fabrication brief with the job. Material choice, tolerances and load capacity are not verified engineering advice.\n\nWhat will the part support or connect, and what dimensions/material do you already know?'
    elif intent == 'specification':
        reply = 'I cannot give an unverified specification. Use the exact model-specific service document.\n\nNo torque, clearance or part number has been established. Open a manufacturer source below; a generic manual is not proof that a value applies.\n\nWhich component and exact engine model are you working on?'
    else:
        reply = 'I can keep your job context and help locate supported references. Live AI is unavailable.\n\nWhat machine or part are you working on, and what do you want to find out?'
    if context.get('response_style') == 'guided' and intent == 'troubleshoot':
        reply += '\n\nTake it one check at a time:\n1. Secure the machine and read its identification plate with the engine stopped.\n2. Tell me what you observed during the last starting attempt; avoid repeated cranking.\n3. Compare that observation with the matching manual before choosing an intrusive test. Stop for leaks, damaged wiring or unsafe conditions.'
    return lead + reply


@router.post('/question')
def ask_question(item: Question):
    # Resolve/replay briefly, then release SQLite before any network or inference.
    with closing(connect()) as c, c:
        existing = c.execute('SELECT job_id,request_question FROM workshop_messages WHERE request_key=?', (str(item.request_key),)).fetchone()
        if existing:
            if existing['request_question'] != item.question or (item.job_id and existing['job_id'] != str(item.job_id)):
                raise HTTPException(409, 'This question request was already used for different details.')
            return get_job(c, existing['job_id'])
        pending = c.execute('SELECT id FROM workshop_jobs WHERE creation_key=?', (str(item.request_key),)).fetchone()
        job_id = str(item.job_id) if item.job_id else pending['id'] if pending else insert_job(c, item.question, str(item.request_key))
        job = get_job(c, job_id)
        revision = job['messages'][-1]['id'] if job['messages'] else 0
        context = route_question(job['context'], item.question)
        local = knowledge.find(c, context, item.question, job_id)
    reply = answering.build(context, item.question, local, reference_reply)
    documents = []
    if not local['needs_online']:
        usable = next((entry for entry in local['findings'] if entry['kind'] == 'document' and entry['sufficient'] and not entry['stale']), None)
        if usable:
            with closing(connect()) as c:
                row = c.execute('SELECT document FROM workshop_sources WHERE id=?', (usable['source_id'],)).fetchone()
            if row:
                snapshot = json.loads(row['document'])
                if snapshot.get('format') == 'pdf':
                    reply = 'From a saved reference (not refreshed):\n\n' + retrieval.extract(snapshot, context.get('task_question', item.question), context)
    if local['needs_online'] and context.get('intent') in ('manual', 'specification', 'parts', 'troubleshoot'):
        research_question = context.get('task_question', item.question)
        context['research_question'] = research_question
        documents, online_reply = retrieval.answer(context, research_question, matching_sources(context))
        if online_reply:
            # Research limitations supplement useful symptom guidance rather than replacing it.
            reply = reply + '\n\nReference lookup: ' + online_reply if context['intent'] == 'troubleshoot' and not documents else online_reply
    timestamp = now()
    with closing(connect()) as c, c:
        c.execute('BEGIN IMMEDIATE')
        existing = c.execute('SELECT job_id,request_question FROM workshop_messages WHERE request_key=?', (str(item.request_key),)).fetchone()
        if existing:
            if existing['request_question'] != item.question: raise HTTPException(409, 'Request key reused.')
            return get_job(c, existing['job_id'])
        current = c.execute('SELECT COALESCE(MAX(id),0) FROM workshop_messages WHERE job_id=?', (job_id,)).fetchone()[0]
        if current != revision: raise HTTPException(409, 'Another answer arrived. Please ask again using the updated conversation.')
        context['_research'] = json.dumps(dict(findings=local['findings'], needs_online=local['needs_online'], plan=search_providers.search_plan(context, item.question)))
        c.execute('INSERT INTO workshop_messages(job_id,role,content,created_at,request_key,request_question) VALUES(?,?,?,?,?,?)', (job_id, 'user', item.question, timestamp, str(item.request_key), item.question))
        c.execute('INSERT INTO workshop_messages(job_id,role,content,created_at) VALUES(?,?,?,?)', (job_id, 'assistant', reply, timestamp))
        c.execute('UPDATE workshop_jobs SET context=?,updated_at=? WHERE id=?', (json.dumps(context), timestamp, job_id))
        for source in matching_sources(context):
            c.execute('INSERT OR IGNORE INTO workshop_sources(job_id,url,title,updated_at) VALUES(?,?,?,?)', (job_id, source['url'], source['title'], timestamp))
        for finding in local['findings']:
            if finding['kind'] == 'document' and finding.get('sufficient') and not finding['stale']:
                row = c.execute('SELECT document FROM workshop_sources WHERE id=?', (finding['source_id'],)).fetchone()
                if row:
                    c.execute('INSERT OR IGNORE INTO workshop_sources(job_id,url,title,document,updated_at) VALUES(?,?,?,?,?)', (job_id, finding['url'], finding['title'], row['document'], timestamp))
        for doc in documents:
            c.execute('INSERT INTO workshop_sources(job_id,url,title,document,updated_at) VALUES(?,?,?,?,?) ON CONFLICT(job_id,url) DO UPDATE SET document=excluded.document,updated_at=excluded.updated_at', (job_id, doc['url'], doc.get('title',doc['url']), json.dumps(doc), timestamp))
        return get_job(c, job_id)


@router.post('/{job_id}/reference')
def read_job_reference(job_id: UUID, item: research.DocumentRequest):
    with closing(connect()) as c:
        get_job(c, job_id)
        row = c.execute('SELECT document FROM workshop_sources WHERE job_id=? AND url=?', (str(job_id), item.url)).fetchone()
        if row and row['document']:
            job = get_job(c, job_id)
            return dict(job=job, document=focus_document(json.loads(row['document']), job['context']), cached=True)
    # The transaction is kept short: no network request holds the DB write lock.
    document = focus_document(research.document(item), get_context(job_id))
    document.update(retrieved_at=now(), saved_context=get_context(job_id), verification_status='source read; applicability unverified')
    with closing(connect()) as c, c:
        timestamp = now()
        c.execute('''INSERT INTO workshop_sources(job_id,url,title,document,updated_at) VALUES(?,?,?,?,?)
                     ON CONFLICT(job_id,url) DO UPDATE SET document=excluded.document,updated_at=excluded.updated_at''',
                  (str(job_id), item.url, document['url'], json.dumps(document), timestamp))
        c.execute('UPDATE workshop_jobs SET updated_at=? WHERE id=?', (timestamp, str(job_id)))
        return dict(job=get_job(c, job_id), document=document, cached=False)


def get_context(job_id):
    with closing(connect()) as c:
        return get_job(c, job_id)['context']


def focus_document(document, context):
    """Show likely document links instead of a manufacturer's entire navigation."""
    result = dict(document)
    links = [entry for entry in document.get('links', [])
             if any(word in (entry['url'] + ' ' + entry.get('title', '')).lower()
                    for word in ('.pdf', 'manual', 'diagram', 'drawing', 'parts-list', 'parts_list', 'wiring', 'hydraulic'))]
    prefix = re.split(r'[\s-]', context.get('serial', ''))[0]
    links.sort(key=lambda entry: (0 if prefix and prefix in entry.get('applicability', '').upper() else 1,
                                 0 if urlsplit(entry['url']).path.lower().endswith('.pdf') else 1))
    result['links'] = links[:60]
    return result
