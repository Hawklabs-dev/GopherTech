"""Install the pinned official Godot CEF runtime; never runs at app startup.

Usage: .venv/bin/python tools/setup_browser.py [--archive /path/to/download.zip]
"""
import argparse
import hashlib
from pathlib import Path
import platform
import tempfile
import urllib.request
import zipfile

VERSION = '2.1.0'
SHA256 = 'debdaec64b5ebc1ef0893ab9f3eea5f72a601ac6fc6d4b42b5ea5d414e9aa103'
URL = f'https://github.com/dsh0416/godot-cef/releases/download/v{VERSION}/godot_cef-store-v{VERSION}.zip'
ROOT = Path(__file__).resolve().parents[1] / 'Godot/gopher-tech'


def install(archive):
    digest = hashlib.sha256()
    with Path(archive).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != SHA256:
        raise ValueError('Browser archive checksum mismatch; nothing installed.')
    targets = {('Linux', 'x86_64'): 'x86_64-unknown-linux-gnu'}
    target = targets.get((platform.system(), platform.machine()))
    if not target:
        raise ValueError('This setup script supports Linux x86_64. Use the upstream release instructions for other platforms.')
    prefix = 'addons/godot_cef/'
    installed = 0
    with zipfile.ZipFile(archive) as bundle:
        for item in bundle.infolist():
            name = item.filename.removeprefix('dist/')
            if not name.startswith(prefix) or item.is_dir():
                continue
            relative = Path(name)
            if '..' in relative.parts:
                raise ValueError('Invalid archive path')
            if '/bin/' in name and not name.startswith(prefix + 'bin/' + target + '/'):
                continue
            destination = ROOT / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(item) as source, destination.open('wb') as output:
                while chunk := source.read(1024 * 1024):
                    output.write(chunk)
            mode = item.external_attr >> 16
            if mode & 0o111:
                destination.chmod(0o755)
            if destination.name == 'gdcef_helper':
                destination.chmod(0o755)
            installed += 1
    if not installed:
        raise ValueError('No browser files found in archive')
    (ROOT / prefix / 'bin/.gdignore').touch()
    print(f'Installed Godot CEF {VERSION} for {target}. Restart the Godot editor once.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    if args.archive:
        install(args.archive)
    else:
        with tempfile.TemporaryDirectory(prefix='gopher-browser-') as folder:
            archive = Path(folder) / 'browser.zip'
            print('Downloading the official browser runtime (about 655 MiB)…', flush=True)
            urllib.request.urlretrieve(URL, archive)
            install(archive)
