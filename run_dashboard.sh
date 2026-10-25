#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if ! command -v godot >/dev/null 2>&1; then
  echo 'Godot is not available on PATH. Open Godot/gopher-tech/project.godot in the editor.' >&2
  exit 1
fi
exec .venv/bin/python launch.py
