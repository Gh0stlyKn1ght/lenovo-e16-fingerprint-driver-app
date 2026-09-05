#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"
require_root
require_command apt-get
require_command apt-mark

pin_backup=''

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

if [ -f "$PIN_FILE" ]; then
  pin_backup=$(mktemp /tmp/goodix-550a-pin.XXXXXX)
  cp -- "$PIN_FILE" "$pin_backup"
fi
trap '[ -z "$pin_backup" ] || rm -f -- "$pin_backup"' EXIT
trap 'rollback_on_error $?' ERR
trap 'rollback_on_error 130' INT
trap 'rollback_on_error 143' TERM HUP
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
udevadm trigger --action=change --subsystem-match=usb --attr-match=idVendor=27c6 --attr-match=idProduct=550a || true
systemctl restart fprintd.service || true
info 'Distribution libfprint restored. Enrolled prints were left intact.'
