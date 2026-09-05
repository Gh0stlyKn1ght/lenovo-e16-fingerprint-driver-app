#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"

pin_backup=''
keep_fingerprints=0

delete_enrolled_fingerprints() {
  local account _ uid
  info 'Deleting enrolled fingerprint templates before removing the driver.'
  if command -v fprintd-delete >/dev/null 2>&1; then
    while IFS=: read -r account _ uid _; do
      [[ "$uid" =~ ^[0-9]+$ ]] || continue
      if (( uid == 0 || (uid >= 1000 && uid < 65534) )); then
        timeout 15 fprintd-delete "$account" >/dev/null 2>&1 || true
      fi
    done < <(getent passwd)
  else
    warn 'fprintd-delete is unavailable; clearing the local template store directly.'
  fi
  systemctl stop fprintd.service >/dev/null \
    || die 'Could not stop fprintd before clearing its template store.'
  clear_fingerprint_data
}

restore_previous_holds() {
  [ -f "$STATE_DIR/holds-before.txt" ] || return 0
  while IFS= read -r package; do
    [ -n "$package" ] || continue
    if dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -qx installed; then
      apt-mark hold "$package" >/dev/null || warn "Could not restore hold for $package."
    fi
  done < "$STATE_DIR/holds-before.txt"
}

restore_pin() {
  [ -n "$pin_backup" ] || return 0
  install -d -o root -g root -m 0755 "$(dirname -- "$PIN_FILE")"
  install -o root -g root -m 0644 "$pin_backup" "$PIN_FILE" \
    || warn "Could not restore APT pin $PIN_FILE."
}

rollback_on_error() {
  local status=$1
  trap - ERR INT TERM HUP
  warn 'Restoration failed; restoring package upgrade protections.'
  restore_pin
  hold_installed_managed_packages
  restore_previous_holds
  exit "$status"
}

main() {
  pin_backup=''
  keep_fingerprints=0
  case "${1:-}" in
    '') ;;
    --keep-fingerprints) keep_fingerprints=1 ;;
    -h|--help)
      printf 'Usage: sudo %s [--keep-fingerprints]\n' "$0"
      return 0 ;;
    *)
      printf 'Usage: sudo %s [--keep-fingerprints]\n' "$0" >&2
      return 2 ;;
  esac
  [ "$#" -le 1 ] || { printf 'Too many arguments.\n' >&2; return 2; }

  require_root
  require_command apt-get
  require_command apt-mark
  require_command find
  require_command getent
  require_command systemctl
  require_command timeout

  if [ -f "$PIN_FILE" ]; then
    pin_backup=$(mktemp /tmp/goodix-550a-pin.XXXXXX)
    cp -- "$PIN_FILE" "$pin_backup"
  fi
  trap '[ -z "$pin_backup" ] || rm -f -- "$pin_backup"' EXIT
  trap 'rollback_on_error $?' ERR
  trap 'rollback_on_error 130' INT
  trap 'rollback_on_error 143' TERM HUP
  if [ "$keep_fingerprints" -eq 1 ]; then
    warn 'Retaining enrolled fingerprint templates by explicit request.'
  else
    delete_enrolled_fingerprints
  fi
  info 'Removing the proprietary Goodix TOD package and APT pin.'
  apt-mark unhold "${MANAGED_PACKAGES[@]}" >/dev/null || true
  apt-get remove -y libfprint-2-tod1-goodix libfprint-2-tod1
  rm -f "$PIN_FILE"
  rm -f /etc/udev/rules.d/99-goodix-550a-kali.rules
  apt-get install -y --reinstall libfprint-2-2 fprintd libpam-fprintd
  restore_previous_holds
  rm -f "$STATE_DIR/holds-before.txt" "$STATE_DIR/preferences.backup"
  trap - ERR INT TERM HUP
  udevadm control --reload-rules
  udevadm trigger --action=change --subsystem-match=usb \
    --attr-match=idVendor=27c6 --attr-match=idProduct=550a || true
  systemctl restart fprintd.service || true
  if [ "$keep_fingerprints" -eq 1 ]; then
    info 'Distribution libfprint restored. Enrolled prints were retained.'
  else
    info 'Distribution libfprint restored. Enrolled prints were deleted.'
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
