"""Audio boundary checks; these never touch SQLite or record a microphone."""
import io
import asyncio
import json
import sys
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi import HTTPException
import voice
import main


def wav(channels=1, width=2, rate=16000, seconds=.1):
    output = io.BytesIO()
    with wave.open(output, 'wb') as audio:
        audio.setnchannels(channels)
        audio.setsampwidth(width)
        audio.setframerate(rate)
        audio.writeframes(b'\0' * int(rate * seconds) * channels * width)
    return output.getvalue()


class VoiceTests(unittest.TestCase):
    def rejected(self, data, code):
        with self.assertRaises(HTTPException) as raised:
            voice.transcribe(data)
        self.assertEqual(raised.exception.status_code, code)

    def test_rejects_non_audio_truncated_and_unsupported_formats(self):
        for data in (b'not audio', wav()[:-10], wav(channels=2), wav(width=1), wav(rate=96000), wav(seconds=0)):
            with self.subTest(size=len(data)):
                self.rejected(data, 422)

    def test_limits_audio_duration_and_request_size(self):
        self.rejected(wav(seconds=31), 422)
        self.rejected(b'\0' * (voice.MAX_BYTES + 1), 413)

    def test_missing_setup_reports_unavailable_without_download(self):
        with patch.object(voice, 'status', return_value={'available':False, 'message':'Install local model'}):
            self.rejected(wav(), 503)

    def test_busy_recognizer_does_not_queue_unbounded_work(self):
        with patch.object(voice, 'status', return_value={'available':True}):
            voice._lock.acquire()
            try:
                self.rejected(wav(), 409)
            finally:
                voice._lock.release()

    def test_recognizer_failure_releases_slot(self):
        with patch.object(voice, 'status', return_value={'available':True}), patch.object(voice, 'load_model', side_effect=RuntimeError('bad model')):
            self.rejected(wav(), 503)
        self.assertTrue(voice._lock.acquire(blocking=False))
        voice._lock.release()


class VoiceRouteTests(unittest.IsolatedAsyncioTestCase):
    async def request(self, method, path, chunks=()):
        events = []
        pending = iter(chunks or (b'',))

        async def receive():
            try:
                chunk = next(pending)
            except StopIteration:
                await asyncio.Future()
            return {'type':'http.request', 'body':chunk, 'more_body':True if chunk else False}

        # Last empty chunk ends the ASGI body, including chunked requests.
        pending = iter((*chunks, b''))

        async def send(event):
            events.append(event)

        scope = {'type':'http', 'asgi':{'version':'3.0'}, 'http_version':'1.1',
                 'method':method, 'scheme':'http', 'path':path, 'raw_path':path.encode(),
                 'query_string':b'', 'root_path':'', 'headers':[(b'content-type', b'audio/wav')],
                 'server':('test', 80), 'client':('test', 1234)}
        await asyncio.wait_for(main.app(scope, receive, send), timeout=5)
        code = next(event['status'] for event in events if event['type'] == 'http.response.start')
        return code, json.loads(b''.join(event.get('body', b'') for event in events if event['type'] == 'http.response.body'))

    async def test_audio_bytes_reach_recognizer_without_json_or_disk(self):
        audio = wav()
        with patch.object(voice, 'transcribe', return_value={'text':'honda engine', 'local_only':True}) as recognition:
            code, reply = await self.request('POST', '/voice/transcribe', (audio[:30], audio[30:]))
        self.assertEqual(code, 200)
        self.assertEqual(reply['text'], 'honda engine')
        recognition.assert_called_once_with(audio)

    async def test_chunked_upload_limit_precedes_recognition(self):
        with patch.object(voice, 'transcribe', side_effect=AssertionError('Do not recognize oversized uploads')):
            code, _ = await self.request('POST', '/voice/transcribe', (b'a' * voice.MAX_BYTES, b'b'))
        self.assertEqual(code, 413)

    async def test_unavailable_model_is_an_explicit_capability(self):
        with patch.object(voice, 'status', return_value={'available':False, 'local_only':True}):
            code, reply = await self.request('GET', '/voice/status')
        self.assertEqual(code, 200)
        self.assertFalse(reply['available'])
