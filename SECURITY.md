# Security

This project integrates a proprietary fingerprint driver into an authentication
stack. The Goodix module cannot be audited by this project. It is downloaded
from Lenovo over HTTPS and accepted only when its SHA-256 matches the reviewed
manifest.

Do not report biometric data, enrolled templates, passwords, or full system
logs in public issues. Report installer vulnerabilities privately to the
maintainers once a repository security contact is configured.

Fingerprint authentication must remain a convenience factor. Keep a working
password and recovery path. The installer never enables PAM automatically.

## Biometric data handling

- Enrollment and verification are performed locally by `fprintd` and the
  Goodix TOD module. This project contains no upload or telemetry feature.
- User templates are stored below `/var/lib/fprint/<user>/`. The systemd unit
  creates `/var/lib/fprint` as root-owned mode `0700`, preventing ordinary
  users from traversing or reading the template path.
- The `fprintd` systemd sandbox restricts address families to local IPC and
  netlink. The proprietary module is loaded inside that process and cannot
  create an Internet socket under this policy.
- The template is not a password and should not be treated as secret material
  that can be changed after exposure. Fingerprint login should supplement, not
  replace, a strong password and recovery method.
- libfprint serialization is not documented as application-level encryption.
  Protect templates at rest with full-disk encryption. File permissions alone
  do not protect against an attacker who can remove or boot the storage device.

## Repository safeguards

- Proprietary binaries and biometric artifacts are not stored in Git.
- Diagnostic reports, captures, templates, and `.fprint` files are ignored.
- Uninstall deletes enrolled templates before removing the working driver and
  clears fprintd's local template store unless `--keep-fingerprints` is explicit.
- The installer performs HTTPS downloads only from reviewed Lenovo and
  Canonical locations and verifies pinned SHA-256 hashes before extraction.
- A weekly workflow re-downloads every artifact, verifies its hash, and checks
  the pinned TOD package against the current Ubuntu Noble update metadata.
- A late, device-specific udev rule limits raw `27c6:550a` access to root-run
  `fprintd` instead of granting desktop users direct sensor access.
- The GUI has no network code. The installer downloads packages but never
  uploads files.
- Issue templates explicitly prohibit attaching templates, captures,
  passwords, USB serial numbers, or other biometric material.

Before publishing, inspect `git remote -v`, `git status`, and `git ls-files`.
Adding a Git remote does not upload anything; only an explicit push does.

## Residual trust and installation risk

- Hash verification proves that an artifact matches the reviewed manifest; it
  does not make the proprietary Goodix module auditable or harmless.
- The first source installation is executed from the checked-out repository.
  Inspect it immediately before authorizing `sudo` or PolicyKit, keep the
  checkout writable only by its owner, and do not run it from a shared folder.
  `sudo ./install-desktop.sh` then installs the persistent GUI and privileged
  helpers below `/usr/libexec/goodix-550a` as `root:root`; the application menu
  never launches privileged helpers from the checkout.
- The foreign TOD stack requires periodic review against newer Canonical and
  Kali packages. Pinned versions reduce accidental ABI breakage but also mean
  security and maintenance updates are not inherited automatically.
- Lenovo's packaged udev rule grants `plugdev` access. This project's later
  exact-device rule resets the node to `root:root` mode `0600`; removing the
  project rule restores Lenovo's broader default.
