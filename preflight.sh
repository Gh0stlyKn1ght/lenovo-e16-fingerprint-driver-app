#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"

status=0
printf '%-28s %s\n' CHECK RESULT
printf '%-28s %s\n' Architecture "$(dpkg --print-architecture)"
[ "$(dpkg --print-architecture)" = amd64 ] || { warn 'The proprietary driver is amd64-only.'; status=1; }

if is_supported_os; then
  printf '%-28s %s\n' 'Operating system' supported
else
  printf '%-28s %s\n' 'Operating system' unsupported
  status=1
fi

if usb_device_present; then
  printf '%-28s %s\n' "USB $TARGET_USB_ID" present
else
  printf '%-28s %s\n' "USB $TARGET_USB_ID" absent
  status=1
fi

printf '%-28s %s\n' 'libfprint-2-2' "$(installed_version libfprint-2-2)"
printf '%-28s %s\n' fprintd "$(installed_version fprintd)"
if has_kali_time64_gusb; then
  printf '%-28s %s\n' 'Kali libgusb ABI' 'libgusb2a (metadata rewrite required)'
else
  printf '%-28s %s\n' 'Kali libgusb ABI' 'libgusb2a not installed'
fi

if [ "$status" -ne 0 ]; then
  die 'Preflight failed. No changes were made.'
fi
info 'Preflight passed. No changes were made.'
