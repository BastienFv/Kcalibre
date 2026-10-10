#!/usr/bin/env bash
# Run the test suite with coverage.
set -euo pipefail
cd "$(dirname "$0")/.."
# Fail instead of rewriting uv.lock when it is out of date.
export UV_LOCKED=1

if [ ! -d tests ] || [ -z "$(find tests -type f -name 'test_*.py' -print -quit)" ]; then
  echo "Aucun fichier de test dans tests/, étape ignorée."
  exit 0
fi

uv run coverage run -m pytest
uv run coverage report
