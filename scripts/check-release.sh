#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

fail=0

bad_files=$(find . -type f \( \
  -name '*.img' -o -name '*.bin' -o -name '*.zip' -o -name '*.7z' -o \
  -name '*.log' -o -name '*.pdf' -o -name '*.exe' -o -name '*.dll' -o \
  -name '*.o' -o -name '*.ko' -o -name '*.kpm' \
\) -not -path './.git/*' -print)
if [ -n "$bad_files" ]; then
  echo "Disallowed files found:" >&2
  echo "$bad_files" >&2
  fail=1
fi

bad_dirs=$(find . -type d \( \
  -name backups -o -name test-reports -o -name platform-tools -o \
  -name toolchain -o -name dist -o -name pkg \
\) -not -path './.git/*' -print)
if [ -n "$bad_dirs" ]; then
  echo "Disallowed directories found:" >&2
  echo "$bad_dirs" >&2
  fail=1
fi

if rg -n -i --hidden --glob '!.git/**' --glob '!scripts/check-release.sh' \
  '(BEGIN [A-Z ]*PRIVATE KEY|api[_-]?key\s*[:=]|client[_-]?secret\s*[:=]|[A-Z]:\\Users\\|/home/[^/[:space:]]+/)' .; then
  echo "Potential secret or absolute user path found." >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "Release hygiene checks passed."
