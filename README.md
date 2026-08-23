# Goodix 550a for Kali and Debian

A safety-oriented installer for the Goodix MOH fingerprint reader
`27c6:550a`. This project makes Lenovo's proprietary Ubuntu TOD driver usable
on current Kali/Debian systems without redistributing the driver.

Created for and initially validated on Kali Linux by
[@ghostlykn1ght](https://github.com/ghostlykn1ght).

## Why this project exists

Upstream libfprint does not support this reader. Lenovo publishes a working
x86-64 TOD plug-in, but current Kali uses the time64 `libgusb2a` package and
standard libfprint without TOD loading. Existing setup scripts install foreign
packages directly, ignore failures, and modify PAM before verifying hardware.

This installer instead:

- accepts only the exact USB ID `27c6:550a` on amd64;
- downloads the proprietary package from Lenovo and verifies its SHA-256;
- verifies Canonical TOD artifacts before use;
- adapts the `libgusb2` dependency metadata to Kali's ABI-compatible
  `libgusb2a` only after checking the shared-library ABI;
- asks APT to simulate the complete transaction first;
- records package state and provides rollback;
- pins the TOD stack against accidental partial upgrades;
- verifies that fprintd sees the device;
- never enables fingerprint PAM automatically.

## Status

Early hardware-validation release. The target ThinkPad E16 Gen 1 AMD detects
the reader as `27c6:550a`; installation still requires an interactive hardware
test. Keep password login enabled.

## Usage

Inspect the system without changing it:

```sh
./preflight.sh
```

Download, verify, and simulate the transaction:

```sh
sudo ./install.sh --dry-run
```

Install after reviewing the dry run:

```sh
sudo ./install.sh
```

Enroll and verify before enabling PAM:

```sh
fprintd-enroll -f right-index-finger
fprintd-verify
sudo pam-auth-update
```

Restore distribution packages:

```sh
sudo ./uninstall.sh
```

Create a sanitized support report:

```sh
./diagnose.sh > diagnostic.txt
```

Review the report before attaching it to an issue. Never share enrolled
templates, biometric captures, passwords, or USB serial numbers.

## Trust and licensing

The installer code is MIT licensed. Goodix's module is proprietary and is not
part of this repository. Lenovo's official archive is fetched at install time.
Canonical's TOD-enabled libfprint packages remain under their respective
licenses. See `SECURITY.md` before using fingerprint authentication.

## Upstream references

- Lenovo package DS560884 / `r1slg01w.zip`
- freedesktop.org libfprint
- Ubuntu's TOD-enabled libfprint packages
- `linux-fingerprint-drivers` device entry for `27c6:550a`

## Credits

Project creation, Kali compatibility direction, and target-hardware validation:
[@ghostlykn1ght](https://github.com/ghostlykn1ght).

See [CONTRIBUTORS.md](CONTRIBUTORS.md) for upstream and community attribution.
