# Full disclosure

This document describes the project's trust boundaries, privileged changes,
data handling, licensing, and known limitations. Read it before installation.

## Project status and affiliation

This is an independent community project. It is not produced, endorsed, or
supported by Lenovo, Goodix, Canonical, the libfprint project, or Kali Linux.
Those names and trademarks belong to their respective owners.

The project has been validated only with the Goodix MOH USB reader
`27c6:550a` in a Lenovo ThinkPad E16 Gen 1 AMD (`21JT`) on amd64 Kali Linux.
It deliberately refuses other USB product IDs and architectures.

## Proprietary code and trust

The working device plug-in is Goodix binary-only code distributed by Lenovo.
Its source is unavailable to this project, so its internal behavior and
security cannot be independently audited. The plug-in is loaded by the
root-run `fprintd` service and processes fingerprint sensor data.

The installer does not redistribute that binary. It downloads Lenovo package
version `0.0.9` from the source recorded in `manifests/releases.conf`, verifies
the pinned SHA-256, and refuses a mismatch. A matching hash proves only that
the download matches the reviewed artifact; it does not prove that the binary
is safe.

The service is restricted with systemd filesystem, privilege, device, syscall,
and network-address-family controls. These controls reduce impact but cannot
make an unauditable privileged binary risk-free.

## Foreign packages and compatibility changes

Kali's standard libfprint does not load this TOD plug-in. Installation uses
pinned Canonical TOD-enabled packages alongside the Lenovo package. Before
installation, the project:

1. verifies each original download against its manifest hash;
2. confirms that the libraries require the `libgusb.so.2` ABI available on
   Kali;
3. changes only the Debian dependency name from Ubuntu's `libgusb2` to Kali's
   time64 `libgusb2a` name;
4. rebuilds packages with root ownership and removes group/other write access;
5. simulates the complete APT transaction before changing the system.

The locally rebuilt packages no longer have the same archive hash as the
original downloads. Their versions are pinned at priority `1001` and held to
prevent an incompatible partial upgrade. This also means normal Kali security
updates for those packages are not inherited automatically. A scheduled
workflow checks artifact hashes and Canonical TOD freshness, but a maintainer
must still review and publish compatible updates.

## Privileged system changes

Driver installation may:

- replace `libfprint-2-2` with the pinned TOD-capable build;
- install `libfprint-2-tod1` and `libfprint-2-tod1-goodix`;
- reinstall `fprintd` and `libpam-fprintd`;
- create `/etc/apt/preferences.d/goodix-550a-kali` and APT holds;
- install a root-only exact-device udev rule and disable runtime USB
  autosuspend for `27c6:550a`;
- store rollback packages and state below `/var/lib/goodix-550a-kali`;
- restart `fprintd.service`.

The optional desktop installer copies reviewed helpers into the root-owned
`/usr/libexec/goodix-550a` directory and installs an application launcher.
PolicyKit authorization is required for driver installation and restoration.

The installer never enables fingerprint PAM automatically. Users must enroll,
verify, retain working password access, and then choose whether to run
`pam-auth-update` themselves.

## Network behavior

The GTK application contains no upload, telemetry, analytics, or update
service. The installer makes outbound HTTPS downloads only for the explicitly
listed Lenovo and Canonical artifacts. Diagnostic output is local and omits
logs by default. The project does not collect biometric data.

## Biometric data and deletion

`fprintd` and the proprietary plug-in process enrollment locally. Templates
are stored below `/var/lib/fprint`, outside this repository, in a mode-`0700`
service state directory. Templates are sensitive, non-revocable biometric
data; they are not passwords or ordinary images.

The filesystem holding `/var/lib/fprint` and every swap device must be
encrypted before enrollment. The application documents but does not enforce
this requirement. Without encryption, an offline attacker may recover current
templates or remnants of deleted data.

Default uninstall asks `fprintd` to delete enrolled records while the working
driver is present, stops the service, and removes every entry in its local
template store. `--keep-fingerprints` is an explicit opt-out. Filesystem
deletion is not guaranteed forensic erasure, particularly on SSDs, snapshots,
backups, or unencrypted media.

## Recovery and failure limits

The installer records prior package state, writes exact pins before package
mutation, reapplies safety holds after ordinary failures or signals, and ships
an uninstaller that restores Kali packages. Power loss, kernel failure, storage
failure, forced termination, or APT/dpkg defects can still leave authentication
packages partially configured. Always retain password access and a bootable
recovery environment.

Uninstall deletes biometric templates before package restoration by default.
That deletion is irreversible even if the later package transaction fails.

## Testing limits

CI checks shell syntax, policy invariants, package contents, recovery control
flow, Python behavior, ShellCheck, Bandit, CodeQL, and upstream artifact
freshness. CI cannot prove the proprietary driver's safety or reproduce every
Kali upgrade, firmware revision, laptop variant, desktop environment, PAM
configuration, or failure mode.

## Licensing and warranty

Original source code and documentation in this repository are licensed under
the MIT License in `LICENSE` and are provided without warranty. Downloaded
Lenovo, Goodix, Canonical, Kali, fprintd, and libfprint components are not
relicensed by this project and remain subject to their own terms. See
`THIRD_PARTY_NOTICES.md`.

