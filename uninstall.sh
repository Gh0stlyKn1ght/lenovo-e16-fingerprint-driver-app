#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"
require_root

info 'Removing the proprietary Goodix TOD package and APT pin.'
apt-get remove -y libfprint-2-tod1-goodix libfprint-2-tod1 || true
rm -f "$PIN_FILE"
rm -f /etc/udev/rules.d/99-goodix-550a-kali.rules
if [ -f "$STATE_DIR/preferences.backup" ]; then
  cp -a "$STATE_DIR/preferences.backup" "$PIN_FILE"
fi
apt-get install -y --reinstall libfprint-2-2 fprintd libpam-fprintd
udevadm control --reload-rules
udevadm trigger --action=change --subsystem-match=usb --attr-match=idVendor=27c6 --attr-match=idProduct=550a || true
systemctl restart fprintd.service || true
info 'Distribution libfprint restored. Enrolled prints were left intact.'
