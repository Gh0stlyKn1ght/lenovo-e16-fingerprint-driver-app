# Contributing

Contributions are welcome for Kali compatibility, packaging, tests,
and documentation. Do not commit proprietary Lenovo or Goodix binaries.

Every artifact change must include its authoritative HTTPS source, SHA-256,
package metadata, and successful `--dry-run` output. Installer changes must
preserve the principles of explicit consent, no automatic PAM modification,
transaction simulation, and a tested rollback path.

Run `./tests/test-static.sh` and ShellCheck before opening a pull request.

Add contributors to `CONTRIBUTORS.md` when their work materially shapes the
project. Preserve attribution from upstream code, packaging, documentation,
and reverse-engineering sources.
