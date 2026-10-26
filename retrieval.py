"""Bounded public manufacturer retrieval; exact extracts, never invented specs."""
import os
import re
from datetime import datetime, timezone
from fastapi import HTTPException
import research
import local_ai


def answer(context, question, sources):
    if os.environ.get('GOPHERTECH_RESEARCH_NETWORK', '1') != '1':
        return [], None
    if not context.get('model'):
        return [], 'What is the model printed on the machine or engine identification plate? I need it to find the right procedure; the brand alone is not enough.'
    if context.get('model') == 'Turf Ranger':
        return [], 'Is this an Exmark Turf Ranger? Please read the model and serial number from its identification plate. The year alone does not establish which specifications or manual apply.'
    # Model libraries are discovery evidence, not proof that every linked manual fits.
    candidates = [s for s in sources if s.get('kind') == 'Model lookup'][:1]
    if not candidates:
        return [], 'I do not yet have a readable source for this model. Your details are saved. No specification or procedure has been verified; manufacturer sites requiring interactive access may need the optional external source link.'
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
        docs.append(pdf)
        return stamp(docs, context), extract(pdf, question, context)
    except (HTTPException, OSError, ValueError) as exc:
        return stamp(docs, context), 'The manufacturer lookup could not complete. No answer or specification has been verified. Saved references remain available; try again when connected. ' + ('The site refused or did not provide a supported document.' if isinstance(exc, HTTPException) else 'Network unavailable.')


def extract(pdf, question, context):
    tokens = set(re.findall(r'[a-z]{3,}', question.lower())) - {'what','where','this','that','find','manual','honda','please','answer','quick','short','give','technical','version','explain','detail'}
    tokens -= set(re.findall(r'[a-z]{3,}', context.get('brand', '').lower() + ' ' + context.get('model', '').lower()))
    if 'drain' in tokens: tokens.update(('oil','draining'))
    passages = []
    for page, text in enumerate(pdf.get('text','').split('\f'), 1):
        for paragraph in re.split(r'\n\s*\n', text):
            paragraph = re.sub(r'\s+', ' ', paragraph).strip()
            score = sum(token in paragraph.lower() for token in tokens)
            if score and 40 < len(paragraph) <= 1000:
                passages.append(dict(text=paragraph, page=page, score=score))
    passages = sorted(passages, key=lambda p:p['score'], reverse=True)[:8]
    ids = local_ai.select(question, passages)
    chosen = [passages[i] for i in ids] if ids is not None else passages[:1]
    mode = 'Local AI selected these source passages' if ids is not None else 'Reference extracts (local AI unavailable)'
    if not chosen:
        return 'The manual was retrieved, but I could not verify an answer in its readable text. Open the saved manual below; diagrams may need the page viewer.'
    if context.get('response_style') == 'quick': chosen = chosen[:1]
    text = '\n\n'.join('Page '+str(p['page'])+': “'+p['text']+'”' for p in chosen)
    text += '\n\n' + mode + '. Exact source extracts; applicability still needs confirmation.'
    text += '\n\nSource: '+pdf['url']+'\nCheck region, variant and the full procedure before use. Secure the machine and follow all precautions in the manual.'
    return text

def stamp(docs, context):
    for doc in docs:
        doc.update(retrieved_at=datetime.now(timezone.utc).isoformat(), saved_context={k:v for k,v in context.items() if not k.startswith('_')}, verification_status='source retrieved; check applicability')
    return docs
