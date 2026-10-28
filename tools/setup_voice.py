"""Explicit free local speech setup. Downloads a pinned 39 MiB English model.

Install requirements-voice.txt first. No download occurs at application startup.
"""
import hashlib
from pathlib import Path
import shutil
import tempfile
import urllib.request
import zipfile

ROOT = Path.home() / '.local/share/gophertech-voice'
NAME = 'vosk-model-small-en-us-0.15'
URL = 'https://alphacephei.com/vosk/models/' + NAME + '.zip'
SHA256 = '30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498'


def main():
    import vosk  # Fail before downloading if the optional runtime is missing.
    ROOT.mkdir(parents=True, exist_ok=True)
    if (ROOT / NAME).exists():
        if not (ROOT / NAME / 'am/final.mdl').is_file():
            raise RuntimeError('Existing model directory is incomplete; refusing to overwrite it.')
        print('Local speech model already installed:', ROOT / NAME)
        return
    with tempfile.TemporaryDirectory(prefix='setup-', dir=ROOT) as temporary:
        folder = Path(temporary)
        archive = folder / 'model.zip'
        print('Downloading free English speech model (39 MiB)…', flush=True)
        with urllib.request.urlopen(URL, timeout=60) as source, archive.open('wb') as target:
            shutil.copyfileobj(source, target)
        with archive.open('rb') as downloaded:
            if hashlib.file_digest(downloaded, 'sha256').hexdigest() != SHA256:
                raise RuntimeError('Speech model failed SHA-256 verification.')
        with zipfile.ZipFile(archive) as source:
            for entry in source.infolist():
                path = Path(entry.filename)
                if path.is_absolute() or '..' in path.parts or path.parts[0] != NAME:
                    raise RuntimeError('Unexpected model archive path.')
            source.extractall(folder)
        (folder / NAME).rename(ROOT / NAME)
    print('Local dictation ready:', ROOT / NAME)


if __name__ == '__main__':
    main()
