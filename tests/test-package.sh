#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
output_dir=$(mktemp -d /tmp/goodix-550a-package-test.XXXXXX)
trap 'rm -rf "$output_dir"' EXIT INT TERM
OUTPUT_DIR="$output_dir" "$ROOT/packaging/build-deb.sh" 0.1.0~test1 >/dev/null
package="$output_dir/lenovo-e16-fingerprint-driver-app_0.1.0~test1_amd64.deb"

[ "$(dpkg-deb -f "$package" Package)" = lenovo-e16-fingerprint-driver-app ]
[ "$(dpkg-deb -f "$package" Architecture)" = amd64 ]
dpkg-deb -f "$package" Depends | grep -qw pkexec
dpkg-deb -f "$package" Depends | grep -qw libglib2.0-bin
if dpkg-deb -f "$package" Depends | grep -qw policykit-1; then
  printf 'Ubuntu-only policykit-1 dependency found in Kali package.\n' >&2
  exit 1
fi
package_listing="$output_dir/package-listing.txt"
dpkg-deb -c "$package" > "$package_listing"
grep -q './usr/libexec/goodix-550a/install.sh' "$package_listing"
grep -q './usr/bin/goodix-550a-gui' "$package_listing"
if grep -Eq '\.(deb|zip|fprint)$|/templates?/|/captures?/' "$package_listing"; then
  printf 'Forbidden artifact found in application package.\n' >&2
  exit 1
fi
sha256sum -c "$package.sha256" >/dev/null

first_hash=$(sha256sum "$package" | cut -d' ' -f1)
OUTPUT_DIR="$output_dir/rebuilt" "$ROOT/packaging/build-deb.sh" 0.1.0~test1 >/dev/null
second_hash=$(sha256sum "$output_dir/rebuilt/$(basename "$package")" | cut -d' ' -f1)
[ "$first_hash" = "$second_hash" ] || {
  printf 'Package build is not reproducible.\n' >&2
  exit 1
}
