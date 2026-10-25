#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ ! -x .venv/bin/python ]]; then
  echo 'The project virtual environment is missing. See README.md.' >&2
  exit 1
fi
exec .venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port 8000
