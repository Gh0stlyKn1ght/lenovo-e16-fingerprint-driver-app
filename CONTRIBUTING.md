# Contributing

Contributions are welcome for Debian-family compatibility, packaging, tests,
and documentation. Do not commit proprietary Lenovo or Goodix binaries.

Every artifact change must include its authoritative HTTPS source, SHA-256,
package metadata, and successful `--dry-run` output. Installer changes must
preserve the principles of explicit consent, no automatic PAM modification,
transaction simulation, and a tested rollback path.

Run `./tests/test-static.sh` and ShellCheck before opening a pull request.
