"""Two app processes and two backend lifetimes sharing one disposable SQLite DB."""
from contextlib import contextmanager
from pathlib import Path
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import database
import main
import research
import uvicorn
from fastapi import HTTPException
from test_research import sample_pdf


@contextmanager
def backend():
    sock = socket.socket()
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(main.app, log_level='warning'))
    thread = threading.Thread(target=server.run, kwargs={'sockets': [sock]}, daemon=True)
    thread.start()
    try:
        deadline = time.monotonic() + 10
        while not server.started and thread.is_alive() and time.monotonic() < deadline:
            time.sleep(.05)
        if not server.started:
            raise RuntimeError('Temporary backend did not start')
        yield f'http://127.0.0.1:{port}'
    finally:
        server.should_exit = True
        thread.join(timeout=10)
        sock.close()


def fixture(url):
    if url.endswith('missing.pdf'):
        raise HTTPException(502, 'Requested document is unavailable')
    if url.endswith('.pdf'):
        return url, 'application/pdf', sample_pdf()
    return url, 'text/html', b'<h1>Original manual fixture</h1><p>Confirm model, serial range and region.</p><a href="/fixture.pdf">Original diagram fixture</a>'


def run():
    project = Path(__file__).resolve().parents[1] / 'Godot/gopher-tech'
    with tempfile.TemporaryDirectory(prefix='gophertech-workorders-') as folder:
        db = Path(folder) / 'prototype.db'
        with patch.object(database, 'DATABASE', db), patch.object(main, 'DATABASE', db):
            for phase in ('workflow', 'reopen'):
                research._cache.clear()
                behavior = patch.object(research, '_download', side_effect=fixture if phase == 'workflow' else AssertionError('Reopen must use saved document'))
                with behavior, backend() as url:
                    env = dict(os.environ, GOPHERTECH_API_URL=url, GOPHERTECH_REOPEN='1' if phase == 'reopen' else '0', PYTHONDONTWRITEBYTECODE='1', GOPHERTECH_PHOTO_ROOT=str(Path(folder) / 'photos'))
                    result = subprocess.run(['godot', '--headless', '--path', str(project), '--log-file', str(Path(folder) / (phase + '.log')), '--script', 'res://work_order_integration.gd'], env=env, timeout=45, check=False)
                    if result.returncode:
                        return result.returncode
    return 0


if __name__ == '__main__':
    sys.exit(run())
