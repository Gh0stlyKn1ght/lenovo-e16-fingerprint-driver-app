#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"

printf '%s\n' '# goodix-550a-kali diagnostic report'
printf 'Generated: %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

printf '%s\n' '## System'
if [ -r /etc/os-release ]; then
  # Print only public distribution fields, never arbitrary environment-style data.
  grep -E '^(ID|ID_LIKE|VERSION_ID|VERSION_CODENAME)=' /etc/os-release || true
fi
printf 'Architecture=%s\n' "$(dpkg --print-architecture)"
printf 'Kernel=%s\n' "$(uname -r)"

printf '\n%s\n' '## Hardware'
if usb_device_present; then
  printf 'USB_ID=%s present\n' "$TARGET_USB_ID"
else
  printf 'USB_ID=%s absent\n' "$TARGET_USB_ID"
fi
for control in /sys/bus/usb/devices/*/power/control; do
  [ -r "$control" ] || continue
  device=${control%/power/control}
  if [ ! -r "$device/idVendor" ] || [ ! -r "$device/idProduct" ]; then
    continue
  fi
  if [ "$(tr '[:upper:]' '[:lower:]' < "$device/idVendor")" = 27c6 ] \
    && [ "$(tr '[:upper:]' '[:lower:]' < "$device/idProduct")" = 550a ]; then
    printf 'power_control=%s\n' "$(cat "$control")"
  fi
done
for field in sys_vendor product_name product_version; do
  if [ -r "/sys/class/dmi/id/$field" ]; then
    printf '%s=' "$field"
    tr -cd '[:alnum:] ._+:-' < "/sys/class/dmi/id/$field"
    printf '\n'
  fi
done

printf '\n%s\n' '## Packages'
for package in libfprint-2-2 libfprint-2-tod1 libfprint-2-tod1-goodix fprintd libpam-fprintd libgusb2a; do
  printf '%s=%s\n' "$package" "$(installed_version "$package")"
done

printf '\n%s\n' '## Service'
systemctl is-active fprintd.service 2>&1 || true
systemctl --no-pager --full status fprintd.service 2>&1 \
  | grep -Ev '(^[[:space:]]*Serial:|[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5})' \
  | tail -30 || true

printf '\n%s\n' '## Recent fprintd log'
journalctl -b -u fprintd.service --no-pager -n 80 2>&1 \
  | grep -Ev '(serial|template|fingerprint data|[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5})' || true

printf '\n%s\n' 'Do not attach enrolled templates or biometric captures.'
