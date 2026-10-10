#!/usr/bin/env bash
# Check formatting, lint and static typing. Never modifies files.
set -euo pipefail
cd "$(dirname "$0")/.."
# Fail instead of rewriting uv.lock when it is out of date.
export UV_LOCKED=1

uv run ruff format --check .
uv run ruff check .

targets=()
for dir in app tests; do
  if [ -d "$dir" ]; then targets+=("$dir"); fi
done
if [ "${#targets[@]}" -eq 0 ]; then
  echo "mypy : aucun code Python (app/, tests/), étape ignorée."
else
  uv run mypy "${targets[@]}"
fi
