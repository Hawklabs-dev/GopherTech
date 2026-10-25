import base64
import shutil
import socket
import unittest
from unittest.mock import patch

import test_api
import research


def sample_pdf():
    """Small original fixture, independent of any manufacturer's copyrighted manual."""
    stream = b'BT /F1 18 Tf 40 120 Td (GopherTech test diagram) Tj ET'
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
               b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
               b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
               b'<< /Length ' + str(len(stream)).encode() + b' >>\nstream\n' + stream + b'\nendstream']
    data = b'%PDF-1.4\n'
    offsets = [0]
    for index, value in enumerate(objects, 1):
        offsets.append(len(data))
        data += str(index).encode() + b' 0 obj\n' + value + b'\nendobj\n'
    xref = len(data)
    data += b'xref\n0 6\n0000000000 65535 f \n'
    data += b''.join(f'{offset:010d} 00000 n \n'.encode() for offset in offsets[1:])
    return data + b'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n' + str(xref).encode() + b'\n%%EOF\n'


class ResearchTests(unittest.IsolatedAsyncioTestCase):
    request = test_api.EquipmentAPITests.request

    async def asyncSetUp(self):
        await test_api.EquipmentAPITests.asyncSetUp(self)
        research._cache.clear()

    async def test_directory_and_model_discovery_are_not_fitment_claims(self):
        with patch.object(research, '_download') as download:
            status, body = await self.request('POST', '/research/sources', {'query': 'Honda GX160 parts diagram'})
        self.assertEqual(status, 200)
        self.assertIn('/gx160', body['sources'][0]['url'])
        self.assertTrue(all(not source['matched_model'] for source in body['sources']))
        self.assertFalse(body['paid_services'])
        download.assert_not_called()

    async def test_paid_ai_stays_disabled(self):
        status, body = await self.request('GET', '/research/status')
        self.assertEqual(status, 200)
        self.assertFalse(body['ai_enabled'])
        self.assertFalse(body['paid_services'])

    async def test_text_and_supported_links_without_scripts(self):
        html = b'<h1>Original fixture manual</h1><script>unsafe script text</script><p>Diagram on page 4</p><a href="/manual.pdf">Manual PDF</a><a href="http://127.0.0.1/private">Private</a><a href="https://other.example/">Other</a>'
        with patch.object(research, '_download', return_value=('https://engines.honda.com/manual', 'text/html', html)):
            status, body = await self.request('POST', '/research/document', {'url': 'https://engines.honda.com/manual'})
        self.assertEqual(status, 200)
        self.assertIn('Diagram on page 4', body['text'])
        self.assertNotIn('unsafe script', body['text'])
        self.assertEqual(body['links'], [dict(title='Manual PDF', url='https://engines.honda.com/manual.pdf')])

    async def test_block_local_unapproved_and_credential_urls(self):
        for url in ['http://127.0.0.1/', 'https://localhost/', 'file:///etc/passwd',
                    'https://engines.honda.com.evil.example/', 'https://user:password@engines.honda.com/',
                    'https://engines.honda.com:444/', 'https://engines.honda.com/\nsecret']:
            with patch.object(research, '_download') as download:
                status, _ = await self.request('POST', '/research/document', {'url': url})
            self.assertEqual(status, 422, url)
            download.assert_not_called()

    async def test_network_failure_returns_clear_error(self):
        with patch.object(research, '_download', side_effect=OSError('network unavailable')):
            status, body = await self.request('POST', '/research/document', {'url': 'https://engines.honda.com/manual'})
        self.assertEqual(status, 502)
        self.assertIn('securely', body['detail'])
        self.assertEqual((await self.request('GET', '/equipment'))[1]['equipment'], [])

    async def test_redirect_cannot_escape_supported_hosts(self):
        with patch.object(research, 'PinnedHTTPS') as connection:
            response = connection.return_value.getresponse.return_value
            response.status = 302
            response.getheader.return_value = 'http://127.0.0.1/private'
            status, _ = await self.request('POST', '/research/document', {'url': 'https://engines.honda.com/manual'})
        self.assertEqual(status, 422)

    def test_dns_private_addresses_rejected_before_connection(self):
        addresses = [(socket.AF_INET, socket.SOCK_STREAM, 6, '', ('127.0.0.1', 443))]
        with patch.object(research.socket, 'getaddrinfo', return_value=addresses), patch.object(research.socket, 'create_connection') as connect:
            with self.assertRaises(ValueError):
                research.PinnedHTTPS('engines.honda.com').connect()
        connect.assert_not_called()

    async def test_cached_document_does_not_fetch_again(self):
        with patch.object(research, '_download', return_value=('https://engines.honda.com/manual', 'text/plain', b'Test manual')) as download:
            for _ in range(2):
                status, _ = await self.request('POST', '/research/document', {'url': 'https://engines.honda.com/manual'})
                self.assertEqual(status, 200)
        self.assertEqual(download.call_count, 1)

    async def test_pdf_text_extraction(self):
        if not shutil.which('pdftotext'):
            self.skipTest('Poppler pdftotext is not installed')
        with patch.object(research, '_download', return_value=('https://engines.honda.com/manual.pdf', 'application/pdf', sample_pdf())):
            status, body = await self.request('POST', '/research/document', {'url': 'https://engines.honda.com/manual.pdf'})
        self.assertEqual(status, 200)
        self.assertEqual(body['format'], 'pdf')
        self.assertIn('GopherTech test diagram', body['text'])

    async def test_pdf_diagram_page_renders_in_app(self):
        if not shutil.which('pdftoppm'):
            self.skipTest('Poppler pdftoppm is not installed')
        with patch.object(research, '_download', return_value=('https://engines.honda.com/manual.pdf', 'application/pdf', sample_pdf())):
            status, body = await self.request('POST', '/research/pdf-page', {'url': 'https://engines.honda.com/manual.pdf', 'page': 1})
        self.assertEqual(status, 200)
        self.assertTrue(base64.b64decode(body['png_base64']).startswith(b'\x89PNG\r\n\x1a\n'))

    async def test_invalid_pdf_page_and_missing_pdf_tools(self):
        for page in (0, 61):
            status, _ = await self.request('POST', '/research/pdf-page', {'url': 'https://engines.honda.com/manual.pdf', 'page': page})
            self.assertEqual(status, 422)
        with patch.object(research, '_download', return_value=('https://engines.honda.com/manual.pdf', 'application/pdf', sample_pdf())), patch.object(research.shutil, 'which', return_value=None):
            status, _ = await self.request('POST', '/research/document', {'url': 'https://engines.honda.com/manual.pdf'})
            self.assertEqual(status, 503)
