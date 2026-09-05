#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"
load_manifest "$ROOT"

ASSUME_YES=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      printf 'Usage: sudo %s [--dry-run] [--yes]\n' "$0"
      exit 0 ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

if [ "$DRY_RUN" -ne 1 ]; then
  require_root
fi
for command in apt-get apt-mark curl dpkg dpkg-deb sha256sum unzip readelf; do require_command "$command"; done
[ "$(dpkg --print-architecture)" = amd64 ] || die 'The Lenovo driver is amd64-only.'
is_supported_os || die 'Only Kali Linux is supported by this installer.'
usb_device_present || die "Fingerprint reader $TARGET_USB_ID was not detected."
has_kali_time64_gusb || die 'Kali time64 package libgusb2a must be installed.'

info "Detected $TARGET_USB_ID. Existing libfprint: $(installed_version libfprint-2-2)"
info 'This installs a proprietary Goodix module into the authentication stack.'
if [ "$ASSUME_YES" -ne 1 ]; then
  printf 'Type the USB ID (%s) to continue: ' "$TARGET_USB_ID"
  read -r confirmation
  [ "$confirmation" = "$TARGET_USB_ID" ] || die 'Confirmation did not match; no changes made.'
fi

workdir=$(mktemp -d /tmp/goodix-550a-install.XXXXXX)
trap 'rm -rf "$workdir"' EXIT INT TERM
mkdir -p "$workdir/downloads" "$workdir/repack"

info 'Downloading verified upstream artifacts.'
download_verified "$LENOVO_URL" "$workdir/downloads/lenovo.zip" "$LENOVO_SHA256"
download_verified "$TOD_URL" "$workdir/downloads/tod.deb" "$TOD_SHA256"
download_verified "$LIBFPRINT_URL" "$workdir/downloads/libfprint.deb" "$LIBFPRINT_SHA256"
unzip -q "$workdir/downloads/lenovo.zip" -d "$workdir/lenovo"

# Lenovo wraps the Debian package in a second ZIP archive.
nested_zip=$(find "$workdir/lenovo" -type f -name '*.zip' -print -quit)
if [ -n "$nested_zip" ]; then
  unzip -q "$nested_zip" -d "$workdir/lenovo/package"
fi

driver_deb=$(find "$workdir/lenovo" -type f -name '*.deb' -print -quit)
[ -n "$driver_deb" ] || die 'Lenovo archive did not contain a Debian package.'
[ "$(dpkg-deb -f "$driver_deb" Package)" = libfprint-2-tod1-goodix ] || die 'Unexpected Lenovo package name.'
[ "$(dpkg-deb -f "$driver_deb" Version)" = "$LENOVO_VERSION" ] || die 'Unexpected Lenovo driver version.'

# The Lenovo archive has historically carried desktop-user ownership and
# group-writable modes.  Never install a root-loaded module with those modes.
dpkg-deb -R "$driver_deb" "$workdir/repack/driver"
find "$workdir/repack/driver" \( -type f -o -type d \) -exec chmod go-w {} +
dpkg-deb --build --root-owner-group "$workdir/repack/driver" "$workdir/driver-kali.deb" >/dev/null
driver_deb="$workdir/driver-kali.deb"

# Kali renamed libgusb2 to libgusb2a during the 64-bit time_t transition. Both
# expose libgusb.so.2; rewrite only the dependency metadata after confirming ABI.
dpkg-deb -R "$workdir/downloads/tod.deb" "$workdir/repack/tod"
sed -i 's/\blibusb2\b/libgusb2a/g; s/\blibgusb2\b/libgusb2a/g' "$workdir/repack/tod/DEBIAN/control"
dpkg-deb -b "$workdir/repack/tod" "$workdir/tod-kali.deb" >/dev/null

dpkg-deb -R "$workdir/downloads/libfprint.deb" "$workdir/repack/libfprint"
sed -i 's/\blibusb2\b/libgusb2a/g; s/\blibgusb2\b/libgusb2a/g' "$workdir/repack/libfprint/DEBIAN/control"
dpkg-deb -b "$workdir/repack/libfprint" "$workdir/libfprint-kali.deb" >/dev/null

readelf -d "$workdir/repack/tod/usr/lib/x86_64-linux-gnu/libfprint-2-tod.so.1" | grep -q 'libgusb.so.2' \
  || die 'Unexpected TOD library ABI; refusing metadata rewrite.'
grep -q 'libgusb.so.2' < <(ldconfig -p) || die 'libgusb runtime ABI is unavailable.'

info 'Simulating package transaction.'
apt-get -s install --allow-downgrades "$workdir/tod-kali.deb" "$workdir/libfprint-kali.deb" "$driver_deb" fprintd libpam-fprintd > "$workdir/apt-simulation.log"
if grep -Eq '^(Remv|Conf) (login|libpam0g|systemd|sudo)\b' "$workdir/apt-simulation.log"; then
  cat "$workdir/apt-simulation.log"
  die 'APT simulation would alter a critical authentication package.'
fi

if [ "$DRY_RUN" -eq 1 ]; then
  cat "$workdir/apt-simulation.log"
  info 'Dry run passed. No packages or configuration were changed.'
  exit 0
fi

install -d -o root -g root -m 0700 "$STATE_DIR" "$STATE_DIR/packages"
chmod 0700 "$STATE_DIR"
dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$STATE_DIR/packages-before.tsv"
cp "$workdir/tod-kali.deb" "$workdir/libfprint-kali.deb" "$driver_deb" "$STATE_DIR/packages/"
[ -e "$PIN_FILE" ] && cp -a "$PIN_FILE" "$STATE_DIR/preferences.backup" || true
if [ -e "$PIN_FILE" ]; then chmod 0600 "$STATE_DIR/preferences.backup"; fi
apt-mark showhold | grep -E '^(libfprint-2-2|libfprint-2-tod1|libfprint-2-tod1-goodix)$' > "$STATE_DIR/holds-before.txt" || true

rollback_on_error() {
  warn "Installation failed. Run $ROOT/uninstall.sh to restore the distribution packages."
}
trap 'rollback_on_error' ERR
apt-get install -y --allow-downgrades "$workdir/tod-kali.deb" "$workdir/libfprint-kali.deb" "$driver_deb" fprintd libpam-fprintd

cat > "$PIN_FILE" <<EOF
Package: libfprint-2-2
Pin: version $LIBFPRINT_VERSION
Pin-Priority: 1001

Package: libfprint-2-tod1
Pin: version $TOD_VERSION
Pin-Priority: 1001

Package: libfprint-2-tod1-goodix
Pin: version $LENOVO_VERSION
Pin-Priority: 1001
EOF
chmod 0644 "$PIN_FILE"
apt-mark hold libfprint-2-2 libfprint-2-tod1 libfprint-2-tod1-goodix >/dev/null

udevadm control --reload-rules
udevadm trigger --subsystem-match=usb --attr-match=idVendor=27c6 --attr-match=idProduct=550a || true
"$ROOT/repair-power.sh"
systemctl restart fprintd.service

if ! timeout 15 fprintd-list "${SUDO_USER:-root}" > "$STATE_DIR/device-test.log" 2>&1; then
  cat "$STATE_DIR/device-test.log" >&2
  die 'Driver installed, but fprintd did not expose the reader. PAM was not changed.'
fi
chmod 0600 "$STATE_DIR"/*.log "$STATE_DIR"/*.tsv 2>/dev/null || true

info 'Reader detected by fprintd. PAM has not been modified.'
info "Enroll with: fprintd-enroll -f right-index-finger ${SUDO_USER:-$USER}"
info 'After successful enrollment and verification, enable PAM explicitly with pam-auth-update.'
