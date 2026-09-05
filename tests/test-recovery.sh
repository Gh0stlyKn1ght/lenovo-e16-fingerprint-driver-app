#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d /tmp/goodix-550a-recovery-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

# shellcheck disable=SC2034
GOODIX_PIN_FILE="$test_root/preferences/goodix-550a-kali"
# shellcheck disable=SC2034
GOODIX_STATE_DIR="$test_root/state"
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
delete_line=$(grep -n '^    delete_enrolled_fingerprints$' "$ROOT/uninstall.sh" | cut -d: -f1)
remove_line=$(grep -n '^[[:space:]]*apt-get remove -y' "$ROOT/uninstall.sh" | cut -d: -f1)
test "$delete_line" -lt "$remove_line" || {
  printf 'Fingerprints must be deleted before the working driver is removed.\n' >&2
  exit 1
}

fingerprint_store="$test_root/fprint"
mkdir -p "$fingerprint_store/device/user"
printf 'sensitive-template\n' > "$fingerprint_store/device/user/template"
clear_fingerprint_test_data "$fingerprint_store"
test -d "$fingerprint_store"
test -z "$(find "$fingerprint_store" -mindepth 1 -print -quit)"

# Source the executable without running it, then exercise both complete control
# flows with every privileged mutation replaced by an in-memory test double.
# shellcheck source=uninstall.sh
. "$ROOT/uninstall.sh"

run_uninstall_case() (
  local operation_log=$1
  shift
  require_root() { :; }
  require_command() { :; }
  delete_enrolled_fingerprints() { printf '%s\n' delete-fingerprints >> "$operation_log"; }
  apt-mark() { printf 'apt-mark %s\n' "$*" >> "$operation_log"; }
  apt-get() { printf 'apt-get %s\n' "$*" >> "$operation_log"; }
  rm() { printf 'rm %s\n' "$*" >> "$operation_log"; }
  udevadm() { printf 'udevadm %s\n' "$*" >> "$operation_log"; }
  systemctl() { printf 'systemctl %s\n' "$*" >> "$operation_log"; }
  restore_previous_holds() { printf '%s\n' restore-holds >> "$operation_log"; }
  main "$@"
)

default_log="$test_root/default-uninstall.log"
run_uninstall_case "$default_log"
grep -qx delete-fingerprints "$default_log"
default_delete_line=$(grep -n '^delete-fingerprints$' "$default_log" | cut -d: -f1)
default_remove_line=$(grep -n '^apt-get remove ' "$default_log" | cut -d: -f1)
test "$default_delete_line" -lt "$default_remove_line"

keep_log="$test_root/keep-uninstall.log"
run_uninstall_case "$keep_log" --keep-fingerprints
if grep -q '^delete-fingerprints$' "$keep_log"; then
  printf '%s\n' 'The explicit retention option unexpectedly deleted fingerprints.' >&2
  exit 1
fi
grep -q '^apt-get remove ' "$keep_log"

delete_log="$test_root/delete-fingerprints.log"
(
  # shellcheck disable=SC2317
  fprintd-delete() { :; }
  getent() {
    printf '%s\n' \
      'root:x:0:0:root:/root:/bin/bash' \
      'daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin' \
      'test-user:x:1000:1000:test:/home/test:/bin/bash'
  }
  timeout() { printf 'timeout %s\n' "$*" >> "$delete_log"; return 1; }
  systemctl() { printf 'systemctl %s\n' "$*" >> "$delete_log"; }
  clear_fingerprint_data() { printf '%s\n' clear-store >> "$delete_log"; }
  delete_enrolled_fingerprints
)
grep -q '^timeout 15 fprintd-delete root$' "$delete_log"
grep -q '^timeout 15 fprintd-delete test-user$' "$delete_log"
if grep -q 'fprintd-delete daemon' "$delete_log"; then
  printf '%s\n' 'A system account was unexpectedly sent for biometric deletion.' >&2
  exit 1
fi
stop_line=$(grep -n '^systemctl stop fprintd.service$' "$delete_log" | cut -d: -f1)
clear_line=$(grep -n '^clear-store$' "$delete_log" | cut -d: -f1)
test "$stop_line" -lt "$clear_line"

stop_failure_log="$test_root/stop-failure.log"
if (
  # shellcheck disable=SC2317
  command() { return 1; }
  systemctl() { return 1; }
  clear_fingerprint_data() { printf '%s\n' unsafe-clear >> "$stop_failure_log"; }
  delete_enrolled_fingerprints
); then
  printf '%s\n' 'Template deletion continued after fprintd failed to stop.' >&2
  exit 1
fi
test ! -e "$stop_failure_log"

if (clear_fingerprint_test_data /tmp/not-a-goodix-recovery-root); then
  printf '%s\n' 'The test-only deletion override accepted an unsafe path.' >&2
  exit 1
fi
