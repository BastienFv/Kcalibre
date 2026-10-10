#!/usr/bin/env bash
# Validate the commit messages of <base>..HEAD (default base: main).
set -euo pipefail
cd "$(dirname "$0")/.."

base="${1:-main}"
if ! git rev-parse --verify --quiet "$base^{commit}" > /dev/null; then
  echo "Référence introuvable : $base" >&2
  exit 2
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Collected first so that a git rev-list failure stops the script (set -e).
shas="$(git rev-list --no-merges --reverse "$base..HEAD")"

count=0
failures=0
while read -r sha; do
  [ -n "$sha" ] || continue
  count=$((count + 1))
  git log -1 --format=%B "$sha" > "$tmp"
  header="$(sed -e 's/\r$//' -e '/^#/d' -e '/^[[:space:]]*$/d' -e q "$tmp")"
  short="$(git rev-parse --short "$sha")"
  case "$header" in
    "fixup! "* | "squash! "* | "amend! "*)
      echo "KO $short $header (commit à réécrire avant fusion)"
      failures=$((failures + 1))
      continue
      ;;
    # Real merges are excluded by --no-merges: this is a regular commit.
    "Merge "*)
      echo "KO $short $header (message de fusion sur un commit ordinaire)"
      failures=$((failures + 1))
      continue
      ;;
  esac
  if reason="$(bash scripts/hooks/commit-msg "$tmp" 2>&1 > /dev/null)"; then
    echo "OK $short $header"
  else
    echo "KO $short $header"
    sed 's/^/   /' <<< "$reason"
    failures=$((failures + 1))
  fi
done <<< "$shas"

if [ "$count" -eq 0 ]; then
  echo "Aucun commit à vérifier ($base..HEAD)."
  exit 0
fi
if [ "$failures" -gt 0 ]; then
  echo "$failures commit(s) invalide(s) sur $count." >&2
  exit 1
fi
