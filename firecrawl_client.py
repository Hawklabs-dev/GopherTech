"""Small REST boundary for Firecrawl search + page reading, with no paid fallback.

Only the fixed Firecrawl endpoint receives requests. Credentials stay in the
backend's environment/private config and never enter jobs or frontend replies.
"""
from dataclasses import asdict
from datetime import datetime, timezone
import ipaddress
import json
import os
from pathlib import Path
import time
import threading
import urllib.error
import urllib.request
from urllib.parse import urlsplit

CONFIG = Path.home() / '.config/gophertech/firecrawl.json'
MAX_RESPONSE = 2 * 1024 * 1024
_cache = {}
_cache_lock = threading.Lock()


def api_key():
    value = os.environ.get('FIRECRAWL_API_KEY', '').strip()
    if value:
        return value
    try:
        value = json.loads(CONFIG.read_text()).get('api_key', '')
        return value.strip() if isinstance(value, str) else ''
    except (OSError, ValueError, AttributeError):
        return ''


def public_url(value):
    if not isinstance(value, str) or len(value) > 2000 or not value.isascii():
        return False
    if any(ord(c) < 33 or ord(c) == 127 or c in '[]\\' for c in value):
        return False
    try:
        parts = urlsplit(value)
        host = parts.hostname or ''
        if (parts.scheme != 'https' or parts.username or parts.password or parts.port not in (None, 443)
                or '.' not in host or host.endswith(('.local', '.internal', '.localhost'))):
            return False
        try:
            return ipaddress.ip_address(host).is_global
        except ValueError:
            return not all(char.isdigit() or char == '.' for char in host)
    except ValueError:
        return False


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _post(payload, key):
    headers = {'Content-Type':'application/json', 'User-Agent':'GopherTech/0.1'}
    if key:
        headers['Authorization'] = 'Bearer ' + key
    request = urllib.request.Request('https://api.firecrawl.dev/v2/search',
                                     data=json.dumps(payload).encode(), headers=headers)
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=15) as response:
        data = response.read(MAX_RESPONSE + 1)
    if len(data) > MAX_RESPONSE:
        raise ValueError('Response too large')
    return json.loads(data)


def search(query):
    from search_providers import SearchResponse
    key = api_key()
    cache_key = (query, bool(key))
    with _cache_lock:
        cached = _cache.get(cache_key)
        if cached and time.monotonic() - cached[0] < 300:
            return SearchResponse(**json.loads(cached[1]))
    payload = dict(query=query[:600], limit=3, sources=['web'], timeout=12000,
                   scrapeOptions=dict(formats=['markdown'], onlyMainContent=True))
    try:
        raw = _post(payload, key)
        if not isinstance(raw, dict) or raw.get('success') is not True:
            raise ValueError('Unsuccessful response')
        data = raw.get('data')
        rows = data.get('web', []) if isinstance(data, dict) else data
        if not isinstance(rows, list):
            raise ValueError('Invalid search response')
        results = []
        for row in rows[:3]:
            if not isinstance(row, dict) or not public_url(row.get('url')):
                continue
            metadata = row.get('metadata') if isinstance(row.get('metadata'), dict) else {}
            text = row.get('markdown', '')
            text = text[:60000] if isinstance(text, str) else ''
            page_code = metadata.get('statusCode', 200)
            if type(page_code) is not int or page_code >= 400:
                text = ''
            title = row.get('title') or metadata.get('title') or row['url']
            results.append(dict(url=row['url'], title=str(title)[:180], text=text,
                                read=bool(text.strip()), retrieved_at=datetime.now(timezone.utc).isoformat(),
                                format='pdf' if '.pdf' in urlsplit(row['url']).path.lower() else 'markdown'))
        result = SearchResponse('firecrawl', 'retrieved' if results else 'empty', query,
                                'Firecrawl searched the web and attempted to read up to three sources.',
                                results=results, results_retrieved=True)
        with _cache_lock:
            if len(_cache) >= 16:
                _cache.pop(next(iter(_cache)))
            _cache[cache_key] = (time.monotonic(), json.dumps(asdict(result)))
        return result
    except urllib.error.HTTPError as exc:
        exc.close()
        messages = {
            401:'Firecrawl authorization is missing or expired. Connect the free account again.',
            402:'Firecrawl credits are exhausted. No paid fallback was started.',
            403:'Firecrawl needs a free account connection before it can research from this network.',
            429:'Firecrawl reached its free-access or request limit. Try later; no paid fallback was started.',
        }
        message = messages.get(exc.code, 'Firecrawl could not complete this search. Try again later.')
        state = 'needs_connection' if exc.code in (401, 403) else 'limit_reached' if exc.code in (402, 429) else 'unavailable'
    except (OSError, ValueError, TypeError):
        state, message = 'unavailable', 'Firecrawl could not return readable search results. Check the connection and retry.'
    return SearchResponse('firecrawl', state, query, message)
