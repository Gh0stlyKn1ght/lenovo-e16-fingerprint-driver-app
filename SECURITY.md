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
- The installer performs HTTPS downloads only from reviewed Lenovo and
  Canonical locations and verifies pinned SHA-256 hashes before extraction.
- The GUI has no network code. The installer downloads packages but never
  uploads files.
- Issue templates explicitly prohibit attaching templates, captures,
  passwords, USB serial numbers, or other biometric material.

Before publishing, inspect `git remote -v`, `git status`, and `git ls-files`.
Adding a Git remote does not upload anything; only an explicit push does.
