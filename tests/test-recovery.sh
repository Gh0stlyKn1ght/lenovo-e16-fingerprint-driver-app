#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d /tmp/goodix-550a-recovery-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

# shellcheck disable=SC2034
GOODIX_PIN_FILE="$test_root/preferences/goodix-550a-kali"
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"

write_pin_file '1:core-test' '1:tod-test' 'driver-test'
test "$(stat -c '%a' "$PIN_FILE")" = 644
grep -q '^Package: libfprint-2-2$' "$PIN_FILE"
grep -q '^Pin: version 1:core-test$' "$PIN_FILE"
grep -q '^Pin: version 1:tod-test$' "$PIN_FILE"
grep -q '^Pin: version driver-test$' "$PIN_FILE"
test "$(grep -c '^Pin-Priority: 1001$' "$PIN_FILE")" -eq 3

hold_log="$test_root/holds.log"
dpkg-query() {
  case "${*: -1}" in
    libfprint-2-2) printf '%s\n' installed ;;
    libfprint-2-tod1) printf '%s\n' half-configured ;;
    libfprint-2-tod1-goodix) printf '%s\n' unpacked ;;
    *) return 1 ;;
  esac
}
apt-mark() {
  printf '%s\n' "$*" >> "$hold_log"
}
hold_installed_managed_packages
test "$(wc -l < "$hold_log")" -eq 3
grep -qx 'hold libfprint-2-2' "$hold_log"
grep -qx 'hold libfprint-2-tod1' "$hold_log"
grep -qx 'hold libfprint-2-tod1-goodix' "$hold_log"

pin_line=$(grep -n 'write_pin_file.*LIBFPRINT_VERSION' "$ROOT/install.sh" | cut -d: -f1)
apt_line=$(grep -n '^apt-get install -y' "$ROOT/install.sh" | cut -d: -f1)
test "$pin_line" -lt "$apt_line" || {
  printf 'The safety pin must be persisted before APT changes packages.\n' >&2
  exit 1
}
grep -q "trap 'installation_failed 130' INT" "$ROOT/install.sh"
grep -q "trap 'installation_failed 143' TERM HUP" "$ROOT/install.sh"
grep -q "trap 'rollback_on_error 130' INT" "$ROOT/uninstall.sh"
grep -q "trap 'rollback_on_error 143' TERM HUP" "$ROOT/uninstall.sh"
delete_line=$(grep -n '^  delete_enrolled_fingerprints$' "$ROOT/uninstall.sh" | cut -d: -f1)
remove_line=$(grep -n '^apt-get remove -y' "$ROOT/uninstall.sh" | cut -d: -f1)
test "$delete_line" -lt "$remove_line" || {
  printf 'Fingerprints must be deleted before the working driver is removed.\n' >&2
  exit 1
}

fingerprint_store="$test_root/fprint"
mkdir -p "$fingerprint_store/device/user"
printf 'sensitive-template\n' > "$fingerprint_store/device/user/template"
GOODIX_FPRINT_DATA_DIR="$fingerprint_store"
FPRINT_DATA_DIR="$GOODIX_FPRINT_DATA_DIR"
clear_fingerprint_data
test -d "$fingerprint_store"
test -z "$(find "$fingerprint_store" -mindepth 1 -print -quit)"
