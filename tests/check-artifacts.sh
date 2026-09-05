#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"
load_manifest "$ROOT"

for command in awk curl dpkg mktemp sha256sum xz; do require_command "$command"; done
check_root=$(mktemp -d /tmp/goodix-550a-artifact-check.XXXXXX)
trap 'rm -rf -- "$check_root"' EXIT

metadata="$check_root/Packages.xz"
package_index="$check_root/Packages"
curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
  --output "$metadata" \
  'https://archive.ubuntu.com/ubuntu/dists/noble-updates/main/binary-amd64/Packages.xz'
xz -dc "$metadata" > "$package_index"
latest_tod=$(awk '
  $0 == "Package: libfprint-2-tod1" { package = 1; next }
  package && /^Version: / { sub(/^Version: /, ""); print; exit }
  /^$/ { package = 0 }
' "$package_index")
[ -n "$latest_tod" ] || die 'Could not determine the current Noble TOD version.'
dpkg --compare-versions "$TOD_VERSION" ge "$latest_tod" \
  || die "TOD manifest is stale: $TOD_VERSION is older than $latest_tod."

download_verified "$LENOVO_URL" "$check_root/lenovo.zip" "$LENOVO_SHA256"
download_verified "$TOD_URL" "$check_root/tod.deb" "$TOD_SHA256"
download_verified "$LIBFPRINT_URL" "$check_root/libfprint.deb" "$LIBFPRINT_SHA256"
info "Artifact hashes are valid and TOD $TOD_VERSION is current."
