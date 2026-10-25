"""Runs Godot against a temporary database on an OS-selected loopback port."""
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
import uvicorn


def run():
    original_database, original_main = database.DATABASE, main.DATABASE
    with tempfile.TemporaryDirectory(prefix='gophertech-integration-') as folder:
        database.DATABASE = main.DATABASE = Path(folder) / 'equipment.db'
        fixture_patch = None
        if '--references' in sys.argv:
            from test_research import sample_pdf
            def fixture_document(url):
                if url.endswith('.pdf'):
                    return url, 'application/pdf', sample_pdf()
                return url, 'text/html', b'<h1>Reference integration fixture</h1><p>Model applicability and diagram page.</p><a href="/gophertech-fixture.pdf">Test diagram PDF</a>'
            fixture_patch = patch('research._download', side_effect=fixture_document)
            fixture_patch.start()
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
            environment = dict(os.environ, GOPHERTECH_API_URL=f'http://127.0.0.1:{port}')
            project = Path(__file__).resolve().parents[1] / 'Godot' / 'gopher-tech'
            script = 'res://finance_integration.gd' if '--finance' in sys.argv else 'res://dashboard_integration.gd'
            if '--references' in sys.argv:
                script = 'res://reference_integration.gd'
            result = subprocess.run(['godot', '--headless', '--path', str(project),
                                     '--log-file', str(Path(folder) / 'godot.log'),
                                     '--script', script],
                                    env=environment, timeout=40, check=False)
            return result.returncode
        finally:
            server.should_exit = True
            thread.join(timeout=10)
            sock.close()
            database.DATABASE, main.DATABASE = original_database, original_main
            if fixture_patch:
                fixture_patch.stop()


if __name__ == '__main__':
    sys.exit(run())
