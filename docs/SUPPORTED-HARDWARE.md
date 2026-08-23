# Supported hardware

Support is determined by the USB identifier, not only by the laptop model.
Run `lsusb` and look for:

```text
27c6:550a Shenzhen Goodix Technology Co.,Ltd. FingerPrint
```

Lenovo may install different fingerprint readers in otherwise identical laptop
models. A machine listed below is supported only when it contains `27c6:550a`.
Readers such as `27c6:55a4` and `27c6:55b4` are not compatible with this driver.

## Compatibility matrix

| Lenovo machine | Evidence | Project status |
| --- | --- | --- |
| ThinkPad E16 Gen 1 AMD, type 21JT | Tested by this project | Hardware-tested on Kali Rolling |
| ThinkPad E14 Gen 4 | Lenovo DS560884 | Vendor-supported on Ubuntu 20.04/22.04; project hardware test wanted |
| ThinkPad E15 Gen 4 | Lenovo DS560884 | Vendor-supported on Ubuntu 20.04/22.04; project hardware test wanted |
| ThinkPad E14 Gen 5, Intel and AMD | Community reports with `27c6:550a` | Compatible candidate; project hardware test wanted |
| ThinkBook 13s Gen 4 | Community report with `27c6:550a` | Compatible candidate; project hardware test wanted |
| ThinkBook 13x Gen 2 IAP | Community report with `27c6:550a` | Compatible candidate; project hardware test wanted |
| ThinkBook 15 Gen 5 ABP | Community report with `27c6:550a` | Compatible candidate; project hardware test wanted |
| IdeaPad Slim 3 16ABR8 | Community report with `27c6:550a` | Compatible candidate; project hardware test wanted |
| IdeaPad 1 15AMN7 | Community report with `27c6:550a` | Compatible candidate; project hardware test wanted |
| IdeaPad Flex 5 (configuration unspecified) | Community report with `27c6:550a` | Compatible candidate; exact machine type needed |

“Compatible candidate” means the reported machine contains the correct sensor;
it is not a guarantee that this project has tested that laptop, distribution,
firmware revision, suspend behavior, or desktop login stack.

## Distribution support

| Distribution | Status | Installation strategy |
| --- | --- | --- |
| Kali Rolling, amd64 | Supported and hardware-tested | Verified Ubuntu TOD packages adapted to Kali's `libgusb2a` transition |
| Debian, Ubuntu, and derivatives | Out of scope | Use a distribution-specific project and native package strategy |
| ARM64 or other architectures | Unsupported | Lenovo publishes this proprietary module for x86-64 only |

This repository intentionally targets Kali Rolling only. Although Lenovo's
upstream binary originated as an Ubuntu package, Ubuntu and Debian require
their own release-specific dependency handling, testing, and recovery paths.
Keeping those implementations separate prevents an untested package strategy
from modifying an authentication stack.

## References

- [Lenovo DS560884: Goodix fingerprint driver for ThinkPad E14 Gen 4 and E15 Gen 4](https://pcsupport.lenovo.com/us/en/downloads/ds560884-goodix-fingerprint-driver-for-linux-thinkpad-e14-gen-4-e15-gen-4)
- [Goodix developer forum: ThinkPad E16 Gen 1 and `27c6:550a`](https://developers.goodix.com/en/bbs/detail/26fab018e2784228872ea17f4d73ccd5)
- [ThinkPad E14 Gen 5 community notes](https://github.com/ramaureirac/thinkpad-e14-linux/blob/main/tweaks/fingerprint/README.md)
- [Fedora discussion: ThinkBook 13s Gen 4](https://discussion.fedoraproject.org/t/what-is-libfprint-tod-and-why-it-is-not-in-official-repos/80026)
- [Fedora discussion: ThinkBook 13x Gen 2 IAP](https://discussion.fedoraproject.org/t/antiderivative-libfprint-tod-goodix-0-0-9/99479?page=2)
- [EndeavourOS discussion: ThinkBook 15 Gen 5 ABP](https://forum.endeavouros.com/t/fingerprint-driver-for-shenzhen-goodix-fingerprint-reader/51715)
- [ArchWiki: IdeaPad Slim 3 16ABR8](https://wiki.archlinux.org/title/Lenovo_IdeaPad_Slim_3_16ABR8)
- [Zorin forum: IdeaPad 1 15AMN7](https://forum.zorin.com/t/new-lenovo-ideapad-1-15amn7-working-fingerprint/37160)
- [Zorin forum: IdeaPad Flex 5](https://forum.zorin.com/t/fingerprint-scanner-lenovo-ideapad-flex-5/37210)

## Add a tested machine

Open a hardware report and include the laptop model, Lenovo machine type,
distribution release, output of `lsusb -d 27c6:550a`, and whether enrollment and
verification completed. Do not attach fingerprint templates, biometric
captures, USB serial numbers, or unsanitized diagnostic files.
