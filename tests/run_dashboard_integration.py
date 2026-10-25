"""Runs Godot against a temporary database on an OS-selected loopback port."""
from pathlib import Path
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import database
import main
import uvicorn


def run():
    original_database, original_main = database.DATABASE, main.DATABASE
    with tempfile.TemporaryDirectory(prefix='gophertech-integration-') as folder:
        database.DATABASE = main.DATABASE = Path(folder) / 'equipment.db'
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


if __name__ == '__main__':
    sys.exit(run())
