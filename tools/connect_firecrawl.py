"""Browser-authorized Firecrawl key setup; never prints or accepts a key in chat."""
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import time
import urllib.request
import webbrowser

CONFIG = Path.home() / '.config/gophertech/firecrawl.json'


def main():
    session = secrets.token_hex(32)
    verifier = secrets.token_urlsafe(32)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
    url = f'https://www.firecrawl.dev/cli-auth?code_challenge={challenge}&source=coding-agent#session_id={session}'
    print('Authorize the free Firecrawl account in your browser:', flush=True)
    print(url, flush=True)
    print('The returned key will be saved privately to ' + str(CONFIG), flush=True)
    webbrowser.open(url)
    deadline = time.monotonic() + 900
    payload = json.dumps({'session_id':session, 'code_verifier':verifier}).encode()
    while time.monotonic() < deadline:
        request = urllib.request.Request('https://www.firecrawl.dev/api/auth/cli/status', data=payload,
                                         headers={'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                result = json.load(response)
        except (OSError, ValueError):
            time.sleep(3)
            continue
        if result.get('status') == 'complete':
            value = result.get('apiKey', '')
            if not isinstance(value, str) or not value.startswith('fc-'):
                raise RuntimeError('Authorization returned no usable key; nothing saved.')
            CONFIG.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            temporary = CONFIG.with_suffix('.tmp')
            fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, 'w') as target:
                json.dump({'api_key':value}, target)
            temporary.replace(CONFIG)
            print('Firecrawl authorization saved. No payment or subscription was requested by this helper.', flush=True)
            return
        time.sleep(3)
    print('Authorization timed out. No key was saved. Run this helper again when ready.', flush=True)


if __name__ == '__main__':
    main()
