#!/usr/bin/env bash

PROJECT_NAME="goodix-550a-kali"
STATE_DIR="${GOODIX_STATE_DIR:-/var/lib/${PROJECT_NAME}}"
PIN_FILE="${GOODIX_PIN_FILE:-/etc/apt/preferences.d/${PROJECT_NAME}}"
TARGET_USB_ID="27c6:550a"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Run this command as root (for example: sudo $0)."
}

load_manifest() {
  local root=$1
  # shellcheck source=../manifests/releases.conf
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
  case "${ID:-}:${ID_LIKE:-}" in
    kali:*|debian:*|*:debian*) return 0 ;;
    *) return 1 ;;
  esac
}

has_kali_time64_gusb() {
  dpkg-query -W -f='${db:Status-Status}' libgusb2a 2>/dev/null | grep -qx installed
}
