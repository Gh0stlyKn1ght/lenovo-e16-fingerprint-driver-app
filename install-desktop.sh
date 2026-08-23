#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
BIN_DIR="${HOME}/.local/bin"
DESKTOP_FILE="$DATA_DIR/applications/io.github.ghostlykn1ght.Goodix550a.desktop"
LAUNCHER="$BIN_DIR/goodix-550a-gui"

if [ "${1:-}" = "--remove" ]; then
  rm -f "$DESKTOP_FILE" "$LAUNCHER"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DATA_DIR/applications" || true
  fi
  printf 'Desktop launcher removed.\n'
  exit 0
fi

if [ "$#" -ne 0 ]; then
  printf 'Usage: %s [--remove]\n' "$0" >&2
  exit 2
fi

mkdir -p "$DATA_DIR/applications" "$BIN_DIR"
ln -sfn "$ROOT/goodix-550a-gui" "$LAUNCHER"
install -m 0644 "$ROOT/io.github.ghostlykn1ght.Goodix550a.desktop" "$DESKTOP_FILE"
sed -i "s|^Exec=.*|Exec=$LAUNCHER|" "$DESKTOP_FILE"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DATA_DIR/applications" || true
fi
printf 'Desktop launcher installed. Open “Goodix Fingerprint Setup” from Settings.\n'
