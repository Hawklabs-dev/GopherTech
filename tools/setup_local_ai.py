"""Install pinned, free local inference files; no accounts, billing or cloud inference.

Downloads about 2.6 GB from the runtime authors and model publisher. Files stay
outside the Git project. Existing unverified files are never overwritten.
"""
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path.home() / '.local/share/gophertech-ai'
RUNTIME_URL = 'https://github.com/ggml-org/llama.cpp/releases/download/b11669/llama-b11669-bin-ubuntu-vulkan-x64.tar.gz'
RUNTIME_SHA = 'e8709e5ba6c1b093dea7f3de57f4aba842f9a188fba6b465782d65d6fcfa4d9f'
MODEL_URL = 'https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/bc640142c66e1fdd12af0bd68f40445458f3869b/Qwen3-4B-Q4_K_M.gguf'
MODEL_SHA = '7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5'


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def download(url, target, expected):
    if target.exists():
        if digest(target) != expected:
            raise RuntimeError('Existing file failed verification; refusing to overwrite: ' + str(target))
        return
    temporary = target.with_suffix(target.suffix + '.part')
    request = urllib.request.Request(url, headers={'User-Agent': 'GopherTech local setup'})
    print('Downloading', target.name, flush=True)
    with urllib.request.urlopen(request, timeout=60) as source, temporary.open('wb') as output:
        shutil.copyfileobj(source, output, 1024 * 1024)
    if digest(temporary) != expected:
        raise RuntimeError('Downloaded file failed SHA-256 verification: ' + str(temporary))
    temporary.rename(target)
    print('Verified', target.name, flush=True)


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    archive = ROOT / 'llama-b11669-vulkan.tar.gz'
    model = ROOT / 'Qwen3-4B-Q4_K_M.gguf'
    download(RUNTIME_URL, archive, RUNTIME_SHA)
    runtime = ROOT / 'runtime-b11669'
    if not runtime.exists():
        with tempfile.TemporaryDirectory(dir=ROOT, prefix='runtime-') as folder:
            with tarfile.open(archive) as source:
                source.extractall(folder, filter='data')
            shutil.copytree(folder, runtime)
    download(MODEL_URL, model, MODEL_SHA)
    servers = list(runtime.rglob('llama-server'))
    if len(servers) != 1:
        raise RuntimeError('Could not identify the verified runtime executable.')
    manifest = dict(runtime=str(servers[0]), model=str(model), model_name='Qwen3-4B-Q4_K_M',
                    runtime_sha256=RUNTIME_SHA, model_sha256=MODEL_SHA, license='Apache-2.0 (model); MIT (runtime)')
    (ROOT / 'installation.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Free local model installed:', ROOT, flush=True)


if __name__ == '__main__':
    main()
