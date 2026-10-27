"""Bounded manufacturer retrieval; unverified PDF text is never a technical answer."""
import os
import re
import queue
import threading
from datetime import datetime, timezone
from fastapi import HTTPException
import research


LOOKUP_TIMEOUT = 8.0
_lookup_slots = threading.BoundedSemaphore(2)


def answer(context, question, sources):
    """Bound interactive waiting even when DNS or a remote server stalls.

    Workers only read documents. Timed-out results cannot later modify a job.
    Limit outstanding workers so retries cannot accumulate unbounded threads.
    """
    if os.environ.get('GOPHERTECH_RESEARCH_NETWORK', '1') != '1':
        return [], None
    if not _lookup_slots.acquire(blocking=False):
        return [], 'Manufacturer research is still busy. Your question is saved; try the reference again shortly.'
    results = queue.Queue(maxsize=1)

    def lookup():
        try:
            results.put(_answer(dict(context), question, sources))
        except Exception:
            results.put(([], 'Manufacturer research failed. No answer or specification has been verified.'))
        finally:
            _lookup_slots.release()

    threading.Thread(target=lookup, daemon=True).start()
    try:
        return results.get(timeout=LOOKUP_TIMEOUT)
    except queue.Empty:
        return [], 'Manufacturer research timed out. No answer or specification has been verified. Your question is saved; retry the reference or use the web search link.'


def _answer(context, question, sources):
    if os.environ.get('GOPHERTECH_RESEARCH_NETWORK', '1') != '1':
        return [], None
    if not context.get('model'):
        return [], 'What is the model printed on the machine or engine identification plate? I need it to find the right procedure; the brand alone is not enough.'
    if context.get('model') == 'Turf Ranger':
        return [], 'Is this an Exmark Turf Ranger? Please read the model and serial number from its identification plate. The year alone does not establish which specifications or manual apply.'
    # Model libraries are discovery evidence, not proof that every linked manual fits.
    candidates = [s for s in sources if s.get('kind') == 'Model lookup'][:1]
    if not candidates:
        return [], ('I recognized ' + context['model'] + ', but automatic reference lookup does not cover this model. '
                    'I cannot verify the requested answer from the sources available here.\n\n'
                    'Use the web search link below to find the manufacturer service manual; confirm the full model, serial range and region before using a specification.')
    docs = []
    try:
        doc = research.document(research.DocumentRequest(url=candidates[0]['url']))
        docs.append(doc)
        serial = re.sub(r'[^A-Z0-9]', '', context.get('serial', '').upper())
        eligible = []
        for link in doc.get('links', []):
            applicability = link.get('applicability', '').upper()
            numbers = re.findall(r'\b\d{7}\b', applicability)
            prefix = re.match(r'[A-Z]+', serial)
            value = re.search(r'\d+', serial)
            if prefix and value and prefix.group() in applicability and len(numbers) >= 2 and int(numbers[0]) <= int(value.group()) <= int(numbers[1]) and '.pdf' in link['url'].lower():
                eligible.append(link)
        if len({link['url'] for link in eligible}) > 1:
            return stamp(docs, context), 'More than one manual matches this serial range. I have not selected a version. Open Sources to compare publication, language and regional coverage.'
        if not eligible:
            if serial and re.search(r'\d', serial):
                return stamp(docs, context), 'I retrieved the manufacturer listing, but could not match the reported serial number to one supported PDF. Please check the prefix and number against the listing below; no procedure or specification is verified.'
            return stamp(docs, context), 'I retrieved the manufacturer’s model manual listing. It contains several versions; I have not chosen one blindly. What is the complete serial prefix and number on the engine? Open Sources to read the listing here.'
        pdf = research.document(research.DocumentRequest(url=eligible[0]['url']))
        reply = extract(pdf, question, context)
        if 'does not establish a match' not in reply:
            docs.append(pdf)
        return stamp(docs, context), reply
    except (HTTPException, OSError, ValueError) as exc:
        return stamp(docs, context), 'The manufacturer lookup could not complete. No answer or specification has been verified. Saved references remain available; try again when connected. ' + ('The site refused or did not provide a supported document.' if isinstance(exc, HTTPException) else 'Network unavailable.')


def extract(pdf, question, context):
    model = context.get('model', '')
    saved = pdf.get('saved_context', {})
    normalize = lambda value: re.sub(r'[^a-z0-9]', '', str(value).lower())
    body = pdf.get('text', '')
    model_pattern = r'(?<![a-z0-9])' + r'[ -]*'.join(re.escape(c) for c in model.lower()) + r'(?![a-z0-9])'
    if not model or (saved.get('model') and normalize(saved['model']) != normalize(model)) or not re.search(model_pattern, body.lower()):
        return 'I could not verify an answer: this document does not establish a match to your machine.\n\nWhat is the full model designation on its identification label?'
    # Keyword selection and PDF extraction do not establish a readable, verified instruction.
    # Keep the original document available through evidence, never promote raw extracts.
    return ('I found a reference for ' + model + ', but could not verify the answer in its readable text. '
            'PDF text can mix columns; inspect the original page before using it.\n\n'
            'Can you confirm the full model designation and serial number on the identification label?')

def stamp(docs, context):
    for doc in docs:
        doc.update(retrieved_at=datetime.now(timezone.utc).isoformat(), saved_context={k:v for k,v in context.items() if not k.startswith('_')}, verification_status='source retrieved; check applicability')
    return docs
