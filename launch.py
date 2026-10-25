"""Launch the existing desktop frontend with its own loopback backend."""
import os
from pathlib import Path
import socket
import subprocess
import threading
import time
import urllib.request
import sys


def main():
    root = Path(__file__).resolve().parent
    os.chdir(root)
    # Each launch owns a private ephemeral port. Never stop an unrelated service.
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    listener.listen(128)
    port = listener.getsockname()[1]
    import uvicorn
    import local_ai
    import main as backend
    server = uvicorn.Server(uvicorn.Config(backend.app, log_level='warning', access_log=False))
    worker = threading.Thread(target=server.run, kwargs={'sockets':[listener]}, daemon=True)
    worker.start()
    url = f'http://127.0.0.1:{port}'
    try:
        for _ in range(100):
            if server.started: break
            if not worker.is_alive(): raise RuntimeError('Backend failed to start')
            time.sleep(.1)
        else: raise RuntimeError('Backend startup timed out')
        env = dict(os.environ, GOPHERTECH_API_URL=url)
        return subprocess.call(['godot', '--path', str(root/'Godot/gopher-tech'), *sys.argv[1:]], env=env)
    finally:
        server.should_exit = True
        worker.join(timeout=5)
        listener.close()


if __name__ == '__main__':
    raise SystemExit(main())
