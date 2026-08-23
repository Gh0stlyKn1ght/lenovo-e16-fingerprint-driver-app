#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="/usr/libexec/goodix-550a"
BIN_FILE="/usr/local/bin/goodix-550a-gui"
DESKTOP_FILE="/usr/local/share/applications/io.github.ghostlykn1ght.Goodix550a.desktop"

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run this command as root (for example: sudo %s).\n' "$0" >&2
  exit 1
fi

remove_legacy_user_launcher() {
  local caller_uid caller_home
  caller_uid=${SUDO_UID:-${PKEXEC_UID:-}}
  [ -n "$caller_uid" ] || return 0
  caller_home=$(getent passwd "$caller_uid" | cut -d: -f6)
  [ -n "$caller_home" ] || return 0
  rm -f -- \
    "$caller_home/.local/bin/goodix-550a-gui" \
    "$caller_home/.local/share/applications/io.github.ghostlykn1ght.Goodix550a.desktop"
}

remove_system_app() {
  rm -f -- "$BIN_FILE" "$DESKTOP_FILE"
  rm -rf -- "$APP_DIR"
  remove_legacy_user_launcher
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/local/share/applications || true
  fi
}

case "${1:-}" in
  '') ;;
  --remove)
    remove_system_app
    printf 'System application removed. Driver packages and fingerprints were not changed.\n'
    exit 0 ;;
  -h|--help)
    printf 'Usage: sudo %s [--remove]\n' "$0"
    exit 0 ;;
  *)
    printf 'Usage: sudo %s [--remove]\n' "$0" >&2
    exit 2 ;;
esac
[ "$#" -le 1 ] || { printf 'Too many arguments.\n' >&2; exit 2; }

for source in \
  goodix-550a-gui goodix_550a_gui.py install.sh uninstall.sh repair-power.sh \
  diagnose.sh preflight.sh lib/common.sh lib/gui_backend.py \
  manifests/releases.conf io.github.ghostlykn1ght.Goodix550a.desktop; do
  [ -f "$ROOT/$source" ] && [ ! -L "$ROOT/$source" ] || {
    printf 'Required source is missing or is a symbolic link: %s\n' "$source" >&2
    exit 1
  }
done

# Clear the previous bundle before copying so obsolete privileged files cannot
# survive an upgrade. APP_DIR is a fixed project-specific path, never user input.
remove_system_app
install -d -o root -g root -m 0755 \
  "$APP_DIR/lib" "$APP_DIR/manifests" /usr/local/bin /usr/local/share/applications
install -o root -g root -m 0755 \
  "$ROOT/goodix-550a-gui" \
  "$ROOT/goodix_550a_gui.py" \
  "$ROOT/install.sh" \
  "$ROOT/uninstall.sh" \
  "$ROOT/repair-power.sh" \
  "$ROOT/diagnose.sh" \
  "$ROOT/preflight.sh" \
  "$APP_DIR/"
install -o root -g root -m 0644 \
  "$ROOT/lib/common.sh" "$ROOT/lib/gui_backend.py" "$APP_DIR/lib/"
install -o root -g root -m 0644 \
  "$ROOT/manifests/releases.conf" "$APP_DIR/manifests/"
ln -s "$APP_DIR/goodix-550a-gui" "$BIN_FILE"
install -o root -g root -m 0644 \
  "$ROOT/io.github.ghostlykn1ght.Goodix550a.desktop" "$DESKTOP_FILE"
sed -i "s|^Exec=.*|Exec=$BIN_FILE|" "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/local/share/applications || true
fi
printf 'Root-owned application installed. Open “Goodix Fingerprint Setup” from Settings.\n'
