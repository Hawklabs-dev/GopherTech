"""Retrieve local source snapshots and observations; never recycle assistant text as fact."""
from datetime import datetime, timezone
import json
import re

FRESH_DAYS = 180
STOP_WORDS = frozenset('a an and are can do does find for from help i in is it me my of on or please the this to what which with your'.split())


def tokens(text):
    return {word for word in re.findall(r'[a-z0-9]+', text.lower()) if len(word) > 2 and word not in STOP_WORDS}


def excerpt(text, words):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return ''
    line = max(lines, key=lambda value: sum(word in value.lower() for word in words))
    if len(line) > 500:
        positions = [line.lower().find(word) for word in words if word in line.lower()]
        start = max(0, min(positions, default=0) - 80)
        return ('…' if start else '') + line[start:start + 500] + '…'
    return line


def find(c, context, question, job_id):
    words = tokens(question + ' ' + context.get('model', ''))
    identity = context.get('model') or context.get('brand')
    findings, seen = [], set()
    asking_notes = any(term in question.lower() for term in ('my notes', 'saved notes', 'saved observations', 'my measurements', 'what did i record'))
    if context.get('model'):
        rows = c.execute('''SELECT id,job_id,url,title,document,updated_at FROM workshop_sources
                            WHERE document IS NOT NULL ORDER BY updated_at DESC LIMIT 100''').fetchall()
        for row in rows:
            if row['url'] in seen:
                continue
            try:
                doc = json.loads(row['document'])
                if not isinstance(doc, dict) or not isinstance(doc.get('text'), str):
                    continue
            except (ValueError, TypeError):
                continue
            saved = doc.get('saved_context', {})
            if not isinstance(saved, dict):
                saved = {}
            # Snapshot identity is frozen at retrieval, unlike a conversation's changing context.
            conflict = any(context.get(name) and saved.get(name) and context[name].lower() != str(saved[name]).lower()
                           for name in ('brand', 'model', 'serial', 'region', 'year'))
            if conflict:
                continue
            body = doc['text']
            haystack = (row['title'] + ' ' + row['url'] + ' ' + body).lower()
            if context.get('model'):
                if not re.search(r'(?<![a-z0-9])' + re.escape(context['model'].lower()) + r'(?![a-z0-9])', haystack):
                    continue
            elif context.get('brand', '').lower() not in haystack:
                continue
            found_words = tokens(haystack)
            score = len(words.intersection(found_words))
            if not score:
                continue
            retrieved = doc.get('retrieved_at', row['updated_at'])
            try:
                stamp = datetime.fromisoformat(retrieved.replace('Z', '+00:00'))
                stale = stamp.tzinfo is None or (datetime.now(timezone.utc) - stamp).days > FRESH_DAYS
            except (ValueError, TypeError):
                stale = True
            # A manual-index page is a useful location, not the actual manual.
            sufficient = doc.get('format') == 'pdf' or not any('.pdf' in link.get('url', '').lower() for link in doc.get('links', []))
            sufficient = sufficient and len(body.strip()) >= 80
            if context.get('intent') == 'manual' and doc.get('format') != 'pdf':
                sufficient = False
            topic_words = tokens(question) - tokens(context.get('brand', '') + ' ' + context.get('model', '')) - {'manual', 'owner', 'please'}
            if topic_words and not topic_words.intersection(tokens(body)):
                sufficient = False
            if context.get('intent') == 'specification':
                sufficient = False  # A keyword match is never verification of a numeric specification.
            kind = context.get('document_kind', '')
            if kind in ('wiring', 'hydraulic', 'exploded', 'diagnostic', 'service'):
                sufficient = sufficient and kind in body.lower()
            findings.append(dict(kind='document', source_id=row['id'], origin_job_id=row['job_id'],
                                 title=row['title'], url=row['url'], excerpt=excerpt(body, words), retrieved_at=retrieved,
                                 verification_status='source_read_applicability_unverified', stale=stale,
                                 sufficient=sufficient, score=score, saved_context=saved))
            seen.add(row['url'])
    # Observations are useful memory but are never promoted to a documented answer.
    row = c.execute('SELECT notes,updated_at FROM workshop_jobs WHERE id=?', (str(job_id),)).fetchone()
    if row and row['notes'].strip() and (asking_notes or words.intersection(tokens(row['notes']))):
        findings.append(dict(kind='observation', origin_job_id=str(job_id), title='Your saved observations',
                             excerpt=excerpt(row['notes'], words), retrieved_at=row['updated_at'],
                             verification_status='user_observation_unverified', stale=False, sufficient=False, score=1))
    findings.sort(key=lambda value: (value.get('stale', False), not value.get('sufficient', False), -value['score']))
    findings = findings[:3]
    usable = any(item['kind'] == 'document' and not item['stale'] and item['sufficient'] for item in findings) or (asking_notes and any(item['kind'] == 'observation' for item in findings))
    return dict(checked=True, findings=findings, needs_online=not usable,
                reason='Saved observations are available; they remain unverified.' if asking_notes and usable else 'A potentially relevant saved document is available; applicability remains unverified.' if usable else 'Local information is missing, older than 180 days, or insufficient for this question.')
