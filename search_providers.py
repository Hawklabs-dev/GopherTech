"""Pure search plans and an explicit future direct-provider boundary.

The browser adapter does not fetch results. No provider here makes a paid call.
"""
from dataclasses import dataclass, field, asdict
import os
import re
from typing import Protocol
from urllib.parse import urlencode


@dataclass
class SearchResponse:
    provider: str
    status: str
    query: str
    message: str
    browser_url: str | None = None
    results: list = field(default_factory=list)
    results_retrieved: bool = False


class SearchProvider(Protocol):
    def plan(self, query: str) -> SearchResponse: ...
    def search(self, query: str) -> SearchResponse: ...


class BrowserProvider:
    def plan(self, query):
        return SearchResponse('browser', 'browser_handoff', query,
                              'Browse this query inside GopherTech. Search results are not automatically read, summarized or verified.',
                              'https://www.google.com/search?' + urlencode({'q': query}))

    def search(self, query):
        return self.plan(query)


class FirecrawlProvider:
    def plan(self, query):
        return SearchResponse('firecrawl', 'ready', query,
                              'Search and read up to three web sources through Firecrawl; confirm applicability before using technical information.')

    def search(self, query):
        import firecrawl_client
        return firecrawl_client.search(query)


class UnavailableProvider:
    def __init__(self, name, message):
        self.name, self.message = name, message

    def plan(self, query):
        return SearchResponse(self.name, 'unavailable', query, self.message)

    def search(self, query):
        return self.plan(query)


def provider() -> SearchProvider:
    name = os.environ.get('GOPHERTECH_SEARCH_PROVIDER', 'firecrawl').strip().lower()
    if name == 'firecrawl':
        return FirecrawlProvider()
    if name == 'browser':
        return BrowserProvider()
    if name == 'disabled':
        return UnavailableProvider('disabled', 'Online research is disabled. Saved information and supported document reading still work.')
    if name == 'api':
        return UnavailableProvider('api', 'Direct search API integration is not implemented or configured. No API call was made; paid services remain paused.')
    return UnavailableProvider(name, 'Unknown search provider. Choose browser, disabled, or the unavailable future api adapter.')


def targeted_query(context, question):
    identity = ' '.join(context.get(name, '') for name in ('year', 'brand', 'model'))
    intent = context.get('intent')
    topic = context.get('document_kind', 'owner') + ' manual manufacturer' if intent == 'manual' else context.get('symptom', question) if intent == 'troubleshoot' else question
    return re.sub(r'\s+', ' ', (identity + ' ' + topic + ' ' + context.get('region', '')).strip())[:600]


def search_plan(context, question):
    # Planning is side-effect free, including when called from a read-only job GET.
    return asdict(provider().plan(targeted_query(context, question)))
