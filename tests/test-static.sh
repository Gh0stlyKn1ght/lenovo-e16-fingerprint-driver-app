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
grep -q '86f21ff6306c20e64e180227982ceb732de5fe574deea92181d829a5cd5be189' "$ROOT/manifests/releases.conf"
grep -q 'pam-auth-update' "$ROOT/README.md"
grep -q 'encrypted before enrolling a fingerprint' "$ROOT/README.md"
grep -q 'full disclosure' "$ROOT/README.md"
grep -q 'proprietary, binary-only' "$ROOT/THIRD_PARTY_NOTICES.md"
grep -q 'Uninstall deletes biometric templates' "$ROOT/docs/FULL-DISCLOSURE.md"
grep -q '/templates/' "$ROOT/.gitignore"
grep -q '\*.fprint' "$ROOT/.gitignore"
grep -q 'MODE="0600", GROUP="root"' "$ROOT/repair-power.sh"
grep -q -- '--include-logs' "$ROOT/diagnose.sh"
grep -q 'APP_DIR="/usr/libexec/goodix-550a"' "$ROOT/install-desktop.sh"
grep -q 'install -o root -g root' "$ROOT/install-desktop.sh"
test "$(grep -c -- '--build --root-owner-group' "$ROOT/install.sh")" -eq 3
grep -q -- '--reinstall --allow-downgrades' "$ROOT/install.sh"
grep -q -- '--allow-change-held-packages' "$ROOT/install.sh"
grep -q 'apt-mark hold libfprint-2-2' "$ROOT/install.sh"
grep -q 'chown root:root' "$ROOT/install.sh"
grep -q 'chmod go-w' "$ROOT/install.sh"
grep -q 'Installer state path must be a real directory' "$ROOT/install.sh"
grep -q "trap 'rollback_on_error \$?' ERR" "$ROOT/uninstall.sh"
grep -q 'hold_installed_managed_packages' "$ROOT/uninstall.sh"
grep -q 'delete_enrolled_fingerprints' "$ROOT/uninstall.sh"
grep -q -- '--keep-fingerprints' "$ROOT/uninstall.sh"
grep -q 'clear_fingerprint_data' "$ROOT/uninstall.sh"
if grep -R -E 'uses:[[:space:]]+[^[:space:]]+@' "$ROOT/.github/workflows" \
  | grep -Ev '@[0-9a-f]{40}([[:space:]]|$)'; then
  printf 'GitHub Actions must be pinned to immutable commit SHAs.\n' >&2
  failed=1
fi
if grep -q 'GOODIX_FPRINT_DATA_DIR' "$ROOT/lib/common.sh" "$ROOT/uninstall.sh"; then
  printf 'The production fingerprint deletion target must not be environment-controlled.\n' >&2
  failed=1
fi
if grep -q -- '-lll' "$ROOT/.github/workflows/shell.yml"; then
  printf 'Bandit must scan all severity levels.\n' >&2
  failed=1
fi
grep -q 'runtime_paths_secure' "$ROOT/lib/gui_backend.py"
grep -q 'package_holds_active' "$ROOT/lib/gui_backend.py"
grep -q 'pin_file_current' "$ROOT/lib/gui_backend.py"
grep -q 'net.reactivated.Fprint.Manager.GetDevices' "$ROOT/lib/common.sh"
if grep -q 'fprintd-list' "$ROOT/install.sh" "$ROOT/lib/gui_backend.py"; then
  printf 'Enrollment listing must not be used for device discovery.\n' >&2
  failed=1
fi
expected_user=$(id -un)
actual_user=$(SUDO_USER='' PKEXEC_UID="$(id -u)" bash -c \
  '. "$1/lib/common.sh"; invoking_user' _ "$ROOT")
[ "$actual_user" = "$expected_user" ] || {
  printf 'PolicyKit caller detection returned %s, expected %s.\n' "$actual_user" "$expected_user" >&2
  failed=1
}
grep -Eq '^Exec=(/usr/local/bin/)?goodix-550a-gui$' "$ROOT/io.github.ghostlykn1ght.Goodix550a.desktop"
if grep -Eq '^[[:space:]]*(sudo[[:space:]]+)?pam-auth-update([[:space:]]|$)' "$ROOT/install.sh"; then
  printf 'The installer must not enable PAM automatically.\n' >&2
  failed=1
fi
if grep -R -nE 'curl[^\n]*\|[[:space:]]*(sudo|bash|sh)|wget[^\n]*\|[[:space:]]*(sudo|bash|sh)' "$ROOT" --include='*.sh'; then
  printf 'Unsafe pipe-to-shell pattern found.\n' >&2
  failed=1
fi
exit "$failed"
