"""Bounded, local-only dictation. Never downloads a model or retains audio."""
from functools import lru_cache
import importlib.util
import io
import json
import os
from pathlib import Path
import threading
import wave

from fastapi import APIRouter, HTTPException, Request
from starlette.concurrency import run_in_threadpool

router = APIRouter(prefix='/voice', tags=['Local dictation'])
MAX_BYTES = 6 * 1024 * 1024
MAX_SECONDS = 30
_lock = threading.Lock()


def model_path():
    return Path(os.environ.get('GOPHERTECH_VOICE_MODEL',
                str(Path.home() / '.local/share/gophertech-voice/vosk-model-small-en-us-0.15')))


def status():
    ready = importlib.util.find_spec('vosk') is not None and (model_path() / 'am/final.mdl').is_file()
    return dict(available=ready, engine='vosk', local_only=True, max_seconds=MAX_SECONDS,
                message='Local dictation ready.' if ready else
                'Local voice setup is missing. Run .venv/bin/python tools/setup_voice.py, then restart the backend.')


@lru_cache(maxsize=1)
def load_model(path):
    from vosk import Model, SetLogLevel
    SetLogLevel(-1)
    # A path prevents the Vosk language/name constructors from downloading files.
    return Model(path)


def transcribe(data):
    if len(data) > MAX_BYTES:
        raise HTTPException(413, 'Keep recordings under 30 seconds.')
    try:
        with wave.open(io.BytesIO(data), 'rb') as audio:
            rate, frames = audio.getframerate(), audio.getnframes()
            if (audio.getnchannels() != 1 or audio.getsampwidth() != 2
                    or audio.getcomptype() != 'NONE' or not 8000 <= rate <= 48000):
                raise HTTPException(422, 'Use mono 16-bit PCM WAV audio at 8–48 kHz.')
            if not frames or frames > rate * MAX_SECONDS:
                raise HTTPException(422, 'Record between a moment and 30 seconds of speech.')
            pcm = audio.readframes(frames)
            if len(pcm) != frames * 2:
                raise HTTPException(422, 'Recording is incomplete. Please try again.')
    except (wave.Error, EOFError, ValueError) as exc:
        raise HTTPException(422, 'Recording was not a readable WAV file.') from exc
    if not status()['available']:
        raise HTTPException(503, status()['message'])
    if not _lock.acquire(blocking=False):
        raise HTTPException(409, 'Another recording is being transcribed. Try again shortly.')
    try:
        from vosk import KaldiRecognizer
        recognizer = KaldiRecognizer(load_model(str(model_path())), rate)
        parts = []
        for offset in range(0, len(pcm), 8000):
            if recognizer.AcceptWaveform(pcm[offset:offset + 8000]):
                parts.append(json.loads(recognizer.Result()).get('text', ''))
        parts.append(json.loads(recognizer.FinalResult()).get('text', ''))
        text = ' '.join(part for part in parts if part).strip()
        return dict(text=text, local_only=True, message='Check names and model numbers before searching.' if text
                    else 'No speech recognized. Check your microphone and try again.')
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, 'Local speech recognition could not start. Check voice setup and retry.') from exc
    finally:
        _lock.release()


@router.get('/status')
def voice_status():
    return status()


@router.post('/transcribe')
async def voice_transcribe(request: Request):
    # Enforce the limit while reading, even when Content-Length is absent.
    data = bytearray()
    async for chunk in request.stream():
        if len(data) + len(chunk) > MAX_BYTES:
            raise HTTPException(413, 'Keep recordings under 30 seconds.')
        data.extend(chunk)
    return await run_in_threadpool(transcribe, bytes(data))
