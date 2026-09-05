# Third-party notices

The MIT License in `LICENSE` applies only to the original source code and
documentation in this repository.

## Goodix fingerprint plug-in distributed by Lenovo

- Component: `libfprint-2-tod1-goodix`
- Version used: `0.0.9`
- Distribution source: Lenovo package DS560884 (`r1slg01w.zip`)
- Status: proprietary, binary-only, downloaded at installation time
- Redistribution: the binary and its Debian package are not included in this
  repository or in the project's application package

Use of the downloaded component is governed by the terms supplied by its
vendor. The project does not grant rights to that component.

## Canonical TOD-enabled libfprint packages

The installer downloads pinned `libfprint-2-2` and `libfprint-2-tod1` Debian
packages from Canonical's official Ubuntu archive. It verifies their hashes,
adapts the `libgusb2` dependency name for Kali's ABI-compatible `libgusb2a`,
and rebuilds them locally. They are not stored or redistributed by this
repository and retain their upstream copyright and license terms. The package
copyright file identifies libfprint as GNU LGPL version 2.1 or later, with NBIS
portions in the United States public domain and Debian packaging under LGPL
2.1. The downloaded package remains the authoritative licensing record.

## Kali, fprintd, libfprint, and other dependencies

Kali packages and the runtime dependencies named in the Debian package remain
under the licenses published by their respective upstream projects and
distributions. The Kali `fprintd` package identifies its principal license as
GNU GPL version 2 or later and includes separately licensed test/support files.
Installing or using this project does not alter those licenses; each installed
package's `/usr/share/doc/<package>/copyright` file is authoritative.

## Trademarks

Lenovo, Goodix, Ubuntu, Canonical, Kali Linux, and other product or project
names are the property of their respective owners. Their use identifies
compatibility and provenance only and does not imply endorsement.
