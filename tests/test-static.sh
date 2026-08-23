#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
failed=0
for file in "$ROOT"/*.sh "$ROOT"/lib/*.sh "$ROOT"/tests/*.sh; do
  bash -n "$file" || failed=1
done
python3 -m unittest discover -s "$ROOT/tests" -p 'test_*.py' || failed=1
python3 -m py_compile "$ROOT/goodix_550a_gui.py" "$ROOT/lib/gui_backend.py" || failed=1

grep -q '27c6:550a' "$ROOT/lib/common.sh"
grep -q 'kali) return 0' "$ROOT/lib/common.sh"
grep -q '860e21edc57cf1399e72e71fd41e0def7639cfe849826ebe4e0492112bc9d897' "$ROOT/manifests/releases.conf"
grep -q 'pam-auth-update' "$ROOT/README.md"
grep -q '/templates/' "$ROOT/.gitignore"
grep -q '\*.fprint' "$ROOT/.gitignore"
grep -q 'MODE="0600", GROUP="root"' "$ROOT/repair-power.sh"
grep -q -- '--include-logs' "$ROOT/diagnose.sh"
if grep -Eq '^[[:space:]]*(sudo[[:space:]]+)?pam-auth-update([[:space:]]|$)' "$ROOT/install.sh"; then
  printf 'The installer must not enable PAM automatically.\n' >&2
  failed=1
fi
if grep -R -nE 'curl[^\n]*\|[[:space:]]*(sudo|bash|sh)|wget[^\n]*\|[[:space:]]*(sudo|bash|sh)' "$ROOT" --include='*.sh'; then
  printf 'Unsafe pipe-to-shell pattern found.\n' >&2
  failed=1
fi
exit "$failed"
