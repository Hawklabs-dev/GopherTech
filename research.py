"""No-cost manufacturer reference discovery and bounded, read-only document viewing.

No search-provider or AI APIs are called. Nothing is written to the application DB.
"""
import base64
from contextlib import closing
from html.parser import HTMLParser
import http.client
import ipaddress
import shutil
import socket
import ssl
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from urllib.parse import urljoin, urlsplit, urlunsplit

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix='/research', tags=['Manufacturer references'])
HOSTS = frozenset({'engines.honda.com', 'engine.honda.ca',
                  'cdn.powerequipment.honda.com', 'www.briggsandstratton.com',
                  'www.briggsracing.com', 'www.vanguardpower.com'})
SOURCES = [
    dict(title='Honda Canada — engine owner manuals', brand='Honda',
         url='https://engine.honda.ca/en/Owners-Manuals',
         kind='Manual library', description='Choose the engine model and confirm the manual applies to your engine.'),
    dict(title='Honda Engines — owner manual library (US)', brand='Honda',
         url='https://engines.honda.com/support-and-service/owners-manuals/',
         kind='Manual library', description='Model-specific manuals; check regional coverage and serial ranges.'),
    dict(title='Briggs & Stratton — manuals and illustrated parts lists', brand='Briggs Stratton',
         url='https://www.briggsandstratton.com/en-us/support/manuals',
         kind='Manuals / parts diagrams', description='Manufacturer lookup for operator manuals and illustrated parts lists. Interactive lookup may need a direct PDF link.'),
    dict(title='Briggs Racing — manuals and engine drawings', brand='Briggs Racing',
         url='https://www.briggsracing.com/support/manuals',
         kind='Manuals / drawings', description='Racing-engine documents. Check the model and publication date.'),
    dict(title='Vanguard — obtaining manuals and parts literature', brand='Vanguard Briggs',
         url='https://www.vanguardpower.com/en-gb/service-and-support/faqs/obtaining-ordering-parts-list-operators-manuals-literature',
         kind='Reference guidance', description='Manufacturer guidance for locating operator, repair and parts literature.'),
]
MAX_BYTES = 8 * 1024 * 1024
MAX_PAGES = 60
_cache = {}
_lock = threading.Lock()
_slots = threading.BoundedSemaphore(2)


class SourceQuery(BaseModel):
    query: str = Field(default='', max_length=600)


class DocumentRequest(BaseModel):
    url: str = Field(min_length=1, max_length=2000)


class PDFPageRequest(DocumentRequest):
    page: int = Field(default=1, ge=1, le=MAX_PAGES)


def approved_url(url):
    try:
        parts = urlsplit(url)
        if (parts.scheme != 'https' or parts.hostname not in HOSTS
                or parts.username or parts.password or parts.port not in (None, 443)
                or not url.isascii() or any(ord(char) < 33 or ord(char) == 127 for char in url)):
            raise ValueError()
        return urlunsplit((parts.scheme, parts.netloc, parts.path or '/', parts.query, ''))
    except ValueError:
        raise HTTPException(422, 'Use an HTTPS link from a supported manufacturer. Local, private and unrelated hosts are not allowed.') from None


class PinnedHTTPS(http.client.HTTPSConnection):
    """Use only a validated public address; keep hostname-based TLS verification."""
    def connect(self):
        addresses = socket.getaddrinfo(self.host, self.port, type=socket.SOCK_STREAM)
        if not addresses or any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
            raise ValueError('Non-public address')
        raw = socket.create_connection((addresses[0][4][0], self.port), timeout=self.timeout)
        try:
            self.sock = self._context.wrap_socket(raw, server_hostname=self.host)
        except Exception:
            raw.close()
            raise


def _download(url):
    current = approved_url(url)
    for _ in range(5):
        parts = urlsplit(current)
        path = parts.path + ('?' + parts.query if parts.query else '')
        with closing(PinnedHTTPS(parts.hostname, timeout=10, context=ssl.create_default_context())) as connection:
            connection.request('GET', path, headers={'User-Agent': 'GopherTech/0.1 reference reader', 'Accept': 'text/html,application/pdf,text/plain', 'Accept-Encoding': 'identity'})
            response = connection.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                current = approved_url(urljoin(current, response.getheader('Location', '')))
                continue
            if response.status != 200:
                raise HTTPException(502, 'The manufacturer declined or could not serve this document. Try another supported source or a direct PDF link.')
            content_type = response.getheader('Content-Type', '').split(';')[0].lower()
            if response.getheader('Content-Encoding', 'identity').lower() not in ('', 'identity'):
                raise HTTPException(422, 'This compressed response is not supported by the bounded document reader.')
            if content_type not in ('text/html', 'application/xhtml+xml', 'application/pdf', 'text/plain', 'application/octet-stream'):
                raise HTTPException(422, 'This reader supports HTML, plain text and PDF documents.')
            deadline = time.monotonic() + 15
            blocks, size = [], 0
            while True:
                if time.monotonic() > deadline:
                    raise HTTPException(504, 'Document download timed out.')
                chunk = response.read(min(65536, MAX_BYTES + 1 - size))
                if not chunk:
                    break
                blocks.append(chunk)
                size += len(chunk)
                if size > MAX_BYTES:
                    raise HTTPException(413, 'This document exceeds the 8 MiB reader limit.')
            data = b''.join(blocks)
            if content_type == 'application/octet-stream' and not data.startswith(b'%PDF-'):
                raise HTTPException(422, 'This download is not a supported PDF document.')
            return current, content_type, data
    raise HTTPException(502, 'Too many document redirects.')


def get_source(url):
    url = approved_url(url)
    with _lock:
        cached = _cache.get(url)
        if cached and time.monotonic() - cached[0] < 300:
            return cached[1]
    if not _slots.acquire(blocking=False):
        raise HTTPException(429, 'The reference reader is busy. Try again shortly.')
    try:
        result = _download(url)
        with _lock:
            if len(_cache) >= 4:
                _cache.pop(next(iter(_cache)))
            _cache[url] = (time.monotonic(), result)
        return result
    except HTTPException:
        raise
    except (OSError, ValueError, http.client.HTTPException):
        raise HTTPException(502, 'Could not reach this manufacturer securely. Check your connection or try another source.') from None
    finally:
        _slots.release()


class ReferenceHTML(HTMLParser):
    def __init__(self, url):
        super().__init__(convert_charrefs=True)
        self.url, self.text, self.links = url, [], []
        self.hidden, self.anchor = 0, None
        self.row_text, self.row_urls = None, []

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style', 'noscript', 'svg'):
            self.hidden += 1
        if self.hidden:
            return
        if tag in ('p', 'div', 'br', 'h1', 'h2', 'h3', 'li', 'tr'):
            self.text.append('\n')
        if tag == 'a':
            href = dict(attrs).get('href', '')
            self.anchor = (urljoin(self.url, href), []) if href else None
        if tag == 'tr':
            self.row_text, self.row_urls = [], []

    def handle_endtag(self, tag):
        if tag in ('script', 'style', 'noscript', 'svg'):
            self.hidden = max(0, self.hidden - 1)
        if tag == 'a' and self.anchor:
            url, label = self.anchor
            try:
                url = approved_url(url)
                if self.row_text is not None:
                    self.row_urls.append(url)
                title = ' '.join(' '.join(label).split()) or urlsplit(url).path.rsplit('/', 1)[-1]
                if title.lower() in ('download', 'pdf', 'view', 'manual'):
                    title += ' — ' + urlsplit(url).path.rsplit('/', 1)[-1]
                if len(self.links) < 100 and not any(item['url'] == url for item in self.links):
                    self.links.append(dict(title=title[:180], url=url))
            except HTTPException:
                pass
            self.anchor = None
        if tag == 'tr' and self.row_text is not None:
            row = ' '.join(' '.join(self.row_text).split())[:500]
            for link in self.links:
                if link['url'] in self.row_urls:
                    link['applicability'] = (link.get('applicability', '') + ' | ' + row).strip(' |')[:1200]
            self.row_text = None

    def handle_data(self, data):
        if not self.hidden:
            self.text.append(data)
            if self.anchor:
                self.anchor[1].append(data)
            if self.row_text is not None:
                self.row_text.append(data)


@router.post('/sources')
def sources(item: SourceQuery):
    query = item.query.strip()
    words = query.lower().split()
    ranked = sorted(SOURCES, key=lambda entry: -sum(word in (entry['title'] + ' ' + entry['brand']).lower() for word in words))
    results = [dict(entry, matched_model=False) for entry in ranked]
    # A model page is a discovery location, never a compatibility claim.
    import re
    model = re.search(r'\b(?:gx|gcv|gc|gxv)\d{2,3}\b', query.lower())
    if model and ('honda' in query.lower() or model.group().startswith('gx')):
        results.insert(0, dict(title='Honda ' + model.group().upper() + ' — model manual lookup', brand='Honda',
                              url='https://engines.honda.com/support-and-service/owners-manuals/' + model.group(),
                              kind='Model lookup', description='Confirm the serial prefix, range and region before choosing a manual. The page may not exist for every model.', matched_model=False))
    return dict(sources=results, message='Manufacturer reference directory, not a live whole-web search. Model fitment, stock and prices are unverified.', paid_services=False)


@router.get('/status')
def research_status():
    return dict(paid_services=False, ai_enabled=False, ai_reason='Paid AI setup and calls are paused by the owner. Local passage selection is optional; see /system/info for its current status.',
                pdf_text=bool(shutil.which('pdftotext')), pdf_pages=bool(shutil.which('pdftoppm')),
                supported_hosts=sorted(HOSTS))


def pdf_text(data):
    executable = shutil.which('pdftotext')
    if not executable:
        raise HTTPException(503, 'PDF text needs the free Poppler pdftotext utility installed on this computer.')
    try:
        result = subprocess.run([executable, '-f', '1', '-l', str(MAX_PAGES), '-layout', '-enc', 'UTF-8', '-', '-'], input=data, capture_output=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        raise HTTPException(422, 'This PDF could not be read within the reader limits.') from None
    if result.returncode:
        raise HTTPException(422, 'This PDF may be encrypted or damaged. Try another manufacturer copy.')
    return result.stdout.decode('utf-8', errors='replace')[:100000]


@router.post('/document')
def document(item: DocumentRequest):
    url, content_type, data = get_source(item.url)
    is_pdf = data.startswith(b'%PDF-') or content_type == 'application/pdf'
    if is_pdf:
        body = pdf_text(data)
        return dict(url=url, format='pdf', text=body or 'No selectable text was found. Use the PDF page viewer for scanned pages and diagrams.',
                    links=[], notice='Text extraction is limited to the first 60 pages and 100,000 characters. Use the PDF page viewer to inspect diagrams and layout.')
    decoded = data.decode('utf-8', errors='replace')
    parser = ReferenceHTML(url)
    if content_type != 'text/plain':
        parser.feed(decoded)
        body = '\n'.join(' '.join(line.split()) for line in ''.join(parser.text).splitlines() if line.strip())
    else:
        body = decoded
    return dict(url=url, format='html' if content_type != 'text/plain' else 'text', text=body[:100000], links=parser.links,
                notice='Text-only manufacturer page; scripts and interactive forms do not run. Select a supported document link below. Content may be incomplete; this is not a verified repair procedure.')


@router.post('/pdf-page')
def pdf_page(item: PDFPageRequest):
    url, content_type, data = get_source(item.url)
    if not data.startswith(b'%PDF-'):
        raise HTTPException(422, 'Choose a PDF document before opening a page image.')
    executable = shutil.which('pdftoppm')
    if not executable:
        raise HTTPException(503, 'PDF page images need the free Poppler pdftoppm utility installed on this computer.')
    with tempfile.TemporaryDirectory(prefix='gophertech-pdf-') as folder:
        output = Path(folder) / 'page'
        try:
            result = subprocess.run([executable, '-f', str(item.page), '-l', str(item.page), '-singlefile', '-scale-to', '1400', '-png', '-', str(output)], input=data, capture_output=True, timeout=12)
        except (OSError, subprocess.TimeoutExpired):
            raise HTTPException(422, 'This PDF page could not be rendered within the reader limits.') from None
        image = output.with_suffix('.png')
        if result.returncode or not image.is_file():
            raise HTTPException(422, 'That PDF page is unavailable. Check the page number or try another document.')
        return dict(url=url, page=item.page, png_base64=base64.b64encode(image.read_bytes()).decode('ascii'))


@router.post('/search')
def search(item: SourceQuery):
    if not item.query.strip():
        raise HTTPException(422, 'Enter a search question.')
    from dataclasses import asdict
    import search_providers
    return asdict(search_providers.provider().search(item.query))
