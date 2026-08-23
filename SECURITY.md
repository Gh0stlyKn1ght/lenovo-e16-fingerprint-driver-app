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
