#!/usr/bin/env bash

PROJECT_NAME="goodix-550a-kali"
# These are consumed by scripts that source this library.
# shellcheck disable=SC2034
STATE_DIR="${GOODIX_STATE_DIR:-/var/lib/${PROJECT_NAME}}"
# shellcheck disable=SC2034
PIN_FILE="${GOODIX_PIN_FILE:-/etc/apt/preferences.d/${PROJECT_NAME}}"
TARGET_USB_ID="27c6:550a"
MANAGED_PACKAGES=(libfprint-2-2 libfprint-2-tod1 libfprint-2-tod1-goodix)

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Run this command as root (for example: sudo $0)."
}

invoking_user() {
  local caller_uid caller_user
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    printf '%s' "$SUDO_USER"
    return 0
  fi

  caller_uid=${PKEXEC_UID:-}
  case "$caller_uid" in
    ''|*[!0-9]*) printf '%s' root; return 0 ;;
  esac
  caller_user=$(getent passwd "$caller_uid" | cut -d: -f1)
  printf '%s' "${caller_user:-root}"
}

load_manifest() {
  local root=$1
  # shellcheck disable=SC1091
  . "$root/manifests/releases.conf"
}

download_verified() {
  local url=$1 output=$2 expected=$3 actual
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
    --output "$output.part" "$url"
  actual=$(sha256sum "$output.part" | awk '{print $1}')
  [ "$actual" = "$expected" ] || {
    rm -f "$output.part"
    die "Checksum mismatch for $url (expected $expected, got $actual)."
  }
  mv "$output.part" "$output"
}

write_pin_file() {
  local libfprint_version=$1 tod_version=$2 driver_version=$3 pin_dir pin_temp
  pin_dir=$(dirname -- "$PIN_FILE")
  [ ! -L "$PIN_FILE" ] || die "APT pin must not be a symbolic link: $PIN_FILE"
  install -d -m 0755 "$pin_dir"
  pin_temp=$(mktemp "$pin_dir/.${PROJECT_NAME}.XXXXXX")
  if ! {
    cat > "$pin_temp" <<EOF
Package: libfprint-2-2
Pin: version $libfprint_version
Pin-Priority: 1001

Package: libfprint-2-tod1
Pin: version $tod_version
Pin-Priority: 1001

Package: libfprint-2-tod1-goodix
Pin: version $driver_version
Pin-Priority: 1001
EOF
    chmod 0644 "$pin_temp"
    mv -fT -- "$pin_temp" "$PIN_FILE"
  }; then
    rm -f -- "$pin_temp"
    return 1
  fi
}

hold_installed_managed_packages() {
  local package status
  for package in "${MANAGED_PACKAGES[@]}"; do
    status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null) || continue
    case "$status" in
      installed|unpacked|half-configured|half-installed|triggers-awaited|triggers-pending)
        apt-mark hold "$package" >/dev/null \
          || warn "Could not apply safety hold for $package." ;;
    esac
  done
}

fprint_device_available() {
  local output
  output=$(timeout 15 gdbus call --system \
    --dest net.reactivated.Fprint \
    --object-path /net/reactivated/Fprint/Manager \
    --method net.reactivated.Fprint.Manager.GetDevices 2>/dev/null) || return 1
  grep -q "objectpath '" <<< "$output" || return 1
  printf '%s\n' "$output"
}

_clear_fingerprint_data_directory() {
  local data_dir=$1
  [ ! -L "$data_dir" ] \
    || die "Fingerprint data path must not be a symbolic link: $data_dir"
  [ -d "$data_dir" ] || return 0
  find "$data_dir" -xdev -mindepth 1 -delete
}

clear_fingerprint_data() {
  _clear_fingerprint_data_directory /var/lib/fprint
}

clear_fingerprint_test_data() {
  local data_dir=$1
  case "$data_dir" in
    /tmp/goodix-550a-recovery-test.*/*) ;;
    *) die 'Test fingerprint data directory is outside the isolated test root.' ;;
  esac
  _clear_fingerprint_data_directory "$data_dir"
}

installed_version() {
  local version
  version=$(dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true)
  printf '%s' "${version:-absent}"
}

usb_device_present() {
  local device vendor product
  for device in /sys/bus/usb/devices/*; do
    [ -r "$device/idVendor" ] || continue
    [ -r "$device/idProduct" ] || continue
    vendor=$(tr '[:upper:]' '[:lower:]' < "$device/idVendor")
    product=$(tr '[:upper:]' '[:lower:]' < "$device/idProduct")
    [ "${vendor}:${product}" = "$TARGET_USB_ID" ] && return 0
  done
  return 1
}

is_supported_os() {
  [ -r /etc/os-release ] || return 1
  # shellcheck source=/dev/null
  . /etc/os-release
  case "${ID:-}" in
    kali) return 0 ;;
    *) return 1 ;;
  esac
}

has_kali_time64_gusb() {
  dpkg-query -W -f='${db:Status-Status}' libgusb2a 2>/dev/null | grep -qx installed
}
