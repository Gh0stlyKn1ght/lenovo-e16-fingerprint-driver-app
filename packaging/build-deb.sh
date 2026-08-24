#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${1:-0.1.0~beta1}
OUTPUT_DIR=${OUTPUT_DIR:-$ROOT/dist}
PACKAGE="lenovo-e16-fingerprint-driver-app"
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-0}

case "$VERSION" in
  *[!0-9A-Za-z.+:~_-]*|'')
    printf 'Invalid Debian version: %s\n' "$VERSION" >&2
    exit 2 ;;
esac

for command in dpkg-deb install sed; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  }
done

workdir=$(mktemp -d /tmp/goodix-550a-package.XXXXXX)
trap 'rm -rf "$workdir"' EXIT INT TERM
stage="$workdir/$PACKAGE"
app="$stage/usr/libexec/goodix-550a"

install -d -m 0755 \
  "$stage/DEBIAN" "$app/lib" "$app/manifests" \
  "$stage/usr/bin" "$stage/usr/share/applications" \
  "$stage/usr/share/doc/$PACKAGE"

install -m 0755 \
  "$ROOT/goodix-550a-gui" "$ROOT/goodix_550a_gui.py" \
  "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/repair-power.sh" \
  "$ROOT/diagnose.sh" "$ROOT/preflight.sh" "$app/"
install -m 0644 "$ROOT/lib/common.sh" "$ROOT/lib/gui_backend.py" "$app/lib/"
install -m 0644 "$ROOT/manifests/releases.conf" "$app/manifests/"
install -m 0644 "$ROOT/README.md" "$ROOT/SECURITY.md" "$ROOT/LICENSE" \
  "$stage/usr/share/doc/$PACKAGE/"

ln -s ../libexec/goodix-550a/goodix-550a-gui "$stage/usr/bin/goodix-550a-gui"
install -m 0644 "$ROOT/io.github.ghostlykn1ght.Goodix550a.desktop" \
  "$stage/usr/share/applications/io.github.ghostlykn1ght.Goodix550a.desktop"
sed -i 's|^Exec=.*|Exec=/usr/bin/goodix-550a-gui|' \
  "$stage/usr/share/applications/io.github.ghostlykn1ght.Goodix550a.desktop"

cat > "$stage/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Gh0stlyKn1ght <26194374+Gh0stlyKn1ght@users.noreply.github.com>
Depends: python3, python3-gi, gir1.2-gtk-3.0, pkexec, fprintd, curl, unzip, binutils
Homepage: https://github.com/Gh0stlyKn1ght/lenovo-e16-fingerprint-driver-app
Description: Kali setup utility for the Goodix 27c6:550a reader
 Installs a root-owned GTK utility and verified installer helpers. The
 proprietary Goodix driver is not included and is fetched from Lenovo only
 after explicit administrator authorization.
EOF

find "$stage" -type d -exec chmod 0755 {} +
mkdir -p "$OUTPUT_DIR"
output="$OUTPUT_DIR/${PACKAGE}_${VERSION}_amd64.deb"
dpkg-deb --root-owner-group --build "$stage" "$output" >/dev/null
sha256sum "$output" > "$output.sha256"
printf '%s\n' "$output"
