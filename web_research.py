"""Find and read web sources; local AI selects exact excerpts, never invents specs."""
from dataclasses import asdict
import os
import queue
import re
import threading
from urllib.parse import urlsplit

import firecrawl_client
import knowledge
import local_ai
import search_providers

LOOKUP_TIMEOUT = 24.0
_slots = threading.BoundedSemaphore(2)


def answer(context, question):
    query = search_providers.targeted_query(context, context.get('task_question', question))
    if os.environ.get('GOPHERTECH_RESEARCH_NETWORK', '1') != '1':
        return [], None, dict(provider='firecrawl', status='disabled', query=query, results_retrieved=False)
    if not _slots.acquire(blocking=False):
        return [], 'Online research is still busy. Try again shortly.', dict(provider='firecrawl', status='busy', query=query, results_retrieved=False)
    results = queue.Queue(maxsize=1)

    def work():
        try:
            results.put(_answer(dict(context), question, query))
        except Exception:
            results.put(([], 'Online research could not complete. No technical answer was verified.',
                         dict(provider='firecrawl', status='unavailable', query=query, results_retrieved=False)))
        finally:
            _slots.release()

    threading.Thread(target=work, daemon=True).start()
    try:
        return results.get(timeout=LOOKUP_TIMEOUT)
    except queue.Empty:
        return [], 'Online research timed out. Your question is saved; retry when connected.', dict(provider='firecrawl', status='timeout', query=query, results_retrieved=False)


def model_matches(model, text):
    if not model:
        return True
    compact = re.sub('[^a-z0-9]', '', model.lower())
    pattern = r'(?<![a-z0-9])' + r'[\s-]*'.join(re.escape(c) for c in compact) + r'(?![a-z0-9])'
    return bool(compact and re.search(pattern, text.lower()))


def manufacturer_source(context, url):
    host = urlsplit(url).hostname or ''
    brand = context.get('brand', '').lower()
    if brand == 'honda':
        return host in {'engines.honda.com', 'engine.honda.ca', 'cdn.powerequipment.honda.com',
                        'www.honda-engines-eu.com', 'www.hondappsv.com'}
    if 'briggs' in brand or 'vanguard' in brand:
        return host in {'www.briggsandstratton.com', 'www.briggsracing.com', 'www.vanguardpower.com'}
    return False


def _answer(context, question, query):
    response = firecrawl_client.search(query)
    return compose(context, question, response)


def from_saved(context, question, document):
    row = dict(url=document['url'], title=document.get('title', document['url']),
               text=document['text'], format=document.get('format', 'markdown'),
               retrieved_at=document.get('retrieved_at', ''), read=True)
    response = search_providers.SearchResponse('firecrawl', 'saved', question,
                                               'Using saved source text without an internet request.',
                                               results=[row], results_retrieved=True)
    docs, reply, report = compose(context, question, response)
    report['refreshed'] = False
    return docs, 'From a saved source (not refreshed):\n\n' + reply, report


def compose(context, question, response):
    report = asdict(response)
    # Full page text belongs in source snapshots, not duplicated in job context.
    report['results'] = [{k:v for k,v in row.items() if k != 'text'} for row in response.results]
    report['selection'] = 'none'
    if not response.results_retrieved:
        return [], response.message, report
    docs, passages = [], []
    topic = knowledge.tokens(question) - knowledge.tokens(context.get('brand', '') + ' ' + context.get('model', ''))
    topic -= {'manual', 'manufacturer', 'owner', 'need', 'want', 'looking'}
    for row in response.results:
        if not row['read']:
            continue
        body = row['text']
        if not model_matches(context.get('model', ''), body):
            continue
        # Video captions can duplicate fragments or omit surrounding instructions.
        if (urlsplit(row['url']).hostname or '') in {'www.youtube.com', 'youtube.com', 'youtu.be'}:
            continue
        document = dict(url=row['url'], title=row['title'], text=body, format=row['format'], links=[],
                        provider='firecrawl', retrieved_at=row['retrieved_at'], saved_context={k:v for k,v in context.items() if not k.startswith('_')},
                        manufacturer_source=manufacturer_source(context, row['url']),
                        verification_status='source read; applicability unverified',
                        notice='Read through Firecrawl. Check machine, model, serial range and region before using technical information.')
        docs.append(document)
        # PDF extraction can scramble tables. Keep the original for inspection.
        if row['format'] == 'pdf':
            continue
        for block in re.split(r'\n\s*\n', body):
            block = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', block)
            block = re.sub(r'\[([^\]]+)\]\([^)]*\)', r'\1', block)
            block = re.sub(r'\s+', ' ', block).strip(' #*')
            if not 40 <= len(block) <= 900 or '|' in block:
                continue
            score = len(topic.intersection(knowledge.tokens(block)))
            if not score:
                continue
            # Never lift a specification from a paragraph for an unspecified model.
            if context.get('intent') == 'specification' and (not context.get('model') or not model_matches(context['model'], block)):
                continue
            passages.append(dict(text=block, url=row['url'], title=row['title'], score=score,
                                 manufacturer_source=document['manufacturer_source']))
    if any(doc['manufacturer_source'] for doc in docs):
        docs = [doc for doc in docs if doc['manufacturer_source']]
        passages = [passage for passage in passages if passage['manufacturer_source']]
    report['pages_read'] = len(docs)
    if not docs:
        if response.results:
            return [], 'I found candidate pages, but could not read a source that establishes a match to this question. No specification or repair procedure is verified. Try a fuller make/model and the exact item you need.', report
        return [], 'Firecrawl found no usable sources for that question. Try the make/model and the exact item you need.', report
    if context.get('intent') == 'manual':
        names = '\n'.join('• ' + doc['title'] for doc in docs)
        return docs, 'I found and read these references:\n\n' + names + '\n\nOpen View source below to inspect them. Confirm the publication, model, serial range and region before choosing a manual.', report
    passages.sort(key=lambda item: -item['score'])
    passages = passages[:6]
    if not passages:
        if any(doc['format'] == 'pdf' for doc in docs):
            return docs, 'I found a matching source manual. Open View source below to inspect the original instructions and diagrams. I have not turned its extracted PDF text into repair instructions; confirm the model, serial range and region first.', report
        return docs, 'I read source pages, but could not isolate a clear answer for your exact question. Open View source below to inspect the original. What is the full model/serial and the specific part or check you need?', report
    selected = local_ai.select(question, passages, timeout=5)
    if selected is None:
        report['selection'] = 'keyword'
        selected = [0]
    else:
        report['selection'] = 'local_ai'
    if not selected:
        return docs, 'The local AI could not find a passage that directly answers this question in the pages read. Open View source below, or narrow the question.', report
    # Exact source excerpts keep every reported fact traceable. No generated repair advice.
    excerpts = []
    used_urls = set()
    for index in selected:
        passage = passages[index]
        if passage['url'] in used_urls:
            continue
        used_urls.add(passage['url'])
        words = passage['text'].split()
        excerpt = ' '.join(words[:25]) + ('…' if len(words) > 25 else '')
        excerpts.append(passage['title'] + ':\n“' + excerpt + '”')
    heading = 'The local AI selected this source text:' if report['selection'] == 'local_ai' else 'I found this matching source text:'
    return docs, heading + '\n\n' + '\n\n'.join(excerpts) + '\n\nCheck model, serial range and region in View source before using a specification or procedure.', report
