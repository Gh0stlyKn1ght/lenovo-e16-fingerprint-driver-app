#!/usr/bin/env bash
set -euo pipefail

RULE_FILE="/etc/udev/rules.d/99-goodix-550a-kali.rules"

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run this command as root (for example: sudo %s).\n' "$0" >&2
  exit 1
fi

install -d -m 0755 /etc/udev/rules.d
cat > "$RULE_FILE" <<'EOF'
# Goodix 27c6:550a can stall mid-enrollment when runtime autosuspend engages.
# This late rule overrides both 60-autosuspend.rules and Lenovo's TOD rule.
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="27c6", ATTR{idProduct}=="550a", TEST=="power/control", ATTR{power/control}="on", ENV{ID_AUTOSUSPEND}="0"
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="27c6", ATTR{idProduct}=="550a", MODE="0600", GROUP="root"
EOF
chmod 0644 "$RULE_FILE"
udevadm control --reload-rules
udevadm trigger --action=change --subsystem-match=usb --attr-match=idVendor=27c6 --attr-match=idProduct=550a

for device in /sys/bus/usb/devices/*; do
  [ -r "$device/idVendor" ] || continue
  [ -r "$device/idProduct" ] || continue
  [ "$(tr '[:upper:]' '[:lower:]' < "$device/idVendor")" = 27c6 ] || continue
  [ "$(tr '[:upper:]' '[:lower:]' < "$device/idProduct")" = 550a ] || continue
  printf 'on' > "$device/power/control"
done

systemctl restart fprintd.service || true
printf 'Goodix 27c6:550a autosuspend disabled.\n'
