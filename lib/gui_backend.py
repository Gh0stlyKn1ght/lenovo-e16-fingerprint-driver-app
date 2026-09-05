"""Read-only system state for the Goodix 550a desktop utility."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os
import pwd
import stat
# Required for fixed-argv status probes; no commands use a shell.
import subprocess  # nosec B404
from typing import Callable

USB_ID = "27c6:550a"
PACKAGES = (
    "libfprint-2-2",
    "libfprint-2-tod1",
    "libfprint-2-tod1-goodix",
    "fprintd",
    "libpam-fprintd",
    "libgusb2a",
)
EXPECTED_TOD_VERSIONS = {
    "libfprint-2-2": "1:1.94.9+tod1-1",
    "libfprint-2-tod1": "1:1.94.7+tod1-0ubuntu5~24.04.9",
    "libfprint-2-tod1-goodix": "0.0.9",
}
DRIVER_VERSION = EXPECTED_TOD_VERSIONS["libfprint-2-tod1-goodix"]
RUNTIME_PATHS = (
    Path("/usr/lib/x86_64-linux-gnu/libfprint-2"),
    Path("/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1"),
    Path(
        "/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/"
        f"libfprint-tod-goodix-550a-{DRIVER_VERSION}.so"
    ),
    Path("/lib/udev/rules.d/60-libfprint-2-tod1-goodix.rules"),
)
PIN_FILE = Path("/etc/apt/preferences.d/goodix-550a-kali")
MANAGED_PACKAGES = frozenset(EXPECTED_TOD_VERSIONS)


@dataclass(frozen=True)
class SystemState:
    reader_present: bool
    driver_installed: bool
    tod_installed: bool
    fprintd_installed: bool
    service_active: bool
    device_available: bool
    package_versions: dict[str, str]
    runtime_paths_secure: bool
    apt_protected: bool

    @property
    def ready(self) -> bool:
        return (
            self.reader_present
            and self.driver_installed
            and self.tod_installed
            and self.fprintd_installed
            and self.device_available
            and self.runtime_paths_secure
            and self.apt_protected
            and all(
                self.package_versions.get(package) == version
                for package, version in EXPECTED_TOD_VERSIONS.items()
            )
        )


def current_user() -> str:
    return os.environ.get("SUDO_USER") or pwd.getpwuid(os.getuid()).pw_name


def reader_present(sysfs_root: Path = Path("/sys/bus/usb/devices")) -> bool:
    if not sysfs_root.is_dir():
        return False
    for device in sysfs_root.iterdir():
        try:
            vendor = (device / "idVendor").read_text(encoding="ascii").strip().lower()
            product = (device / "idProduct").read_text(encoding="ascii").strip().lower()
        except (FileNotFoundError, PermissionError, OSError, UnicodeError):
            continue
        if f"{vendor}:{product}" == USB_ID:
            return True
    return False


def package_versions(
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> dict[str, str]:
    versions: dict[str, str] = {}
    for package in PACKAGES:
        result = runner(
            ["dpkg-query", "-W", "-f=${db:Status-Status}\t${Version}", package],
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode == 0:
            status, _, version = result.stdout.strip().partition("\t")
            if status == "installed" and version:
                versions[package] = version
    return versions


def service_active(
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> bool:
    result = runner(
        ["systemctl", "is-active", "--quiet", "fprintd.service"],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def runtime_paths_secure(
    paths: tuple[Path, ...] = RUNTIME_PATHS,
    expected_uid: int = 0,
    expected_gid: int = 0,
) -> bool:
    """Reject missing, linked, non-root, or group/world-writable driver paths."""
    for path in paths:
        try:
            metadata = path.lstat()
        except (FileNotFoundError, PermissionError, OSError):
            return False
        if stat.S_ISLNK(metadata.st_mode):
            return False
        if not (stat.S_ISDIR(metadata.st_mode) or stat.S_ISREG(metadata.st_mode)):
            return False
        if metadata.st_uid != expected_uid or metadata.st_gid != expected_gid:
            return False
        if metadata.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            return False
    return True


def device_available(
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> bool:
    try:
        result = runner(
            [
                "gdbus",
                "call",
                "--system",
                "--dest",
                "net.reactivated.Fprint",
                "--object-path",
                "/net/reactivated/Fprint/Manager",
                "--method",
                "net.reactivated.Fprint.Manager.GetDevices",
            ],
            text=True,
            capture_output=True,
            check=False,
            timeout=5,
        )
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0 and "objectpath '" in result.stdout


def package_holds_active(
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> bool:
    try:
        result = runner(
            ["apt-mark", "showhold"], text=True, capture_output=True, check=False
        )
    except (FileNotFoundError, OSError):
        return False
    if result.returncode != 0:
        return False
    return MANAGED_PACKAGES.issubset(result.stdout.splitlines())


def pin_file_current(
    path: Path = PIN_FILE,
    expected_uid: int = 0,
    expected_gid: int = 0,
) -> bool:
    try:
        metadata = path.lstat()
        content = path.read_text(encoding="utf-8")
    except (FileNotFoundError, PermissionError, OSError, UnicodeError):
        return False
    if not stat.S_ISREG(metadata.st_mode):
        return False
    if metadata.st_uid != expected_uid or metadata.st_gid != expected_gid:
        return False
    if metadata.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        return False

    pinned: dict[str, str] = {}
    priorities: dict[str, str] = {}
    package = ""
    for line in content.splitlines():
        if line.startswith("Package: "):
            package = line.removeprefix("Package: ").strip()
        elif package and line.startswith("Pin: version "):
            pinned[package] = line.removeprefix("Pin: version ").strip()
        elif package and line.startswith("Pin-Priority: "):
            priorities[package] = line.removeprefix("Pin-Priority: ").strip()
    return pinned == EXPECTED_TOD_VERSIONS and priorities == {
        package: "1001" for package in EXPECTED_TOD_VERSIONS
    }


def collect_state() -> SystemState:
    versions = package_versions()
    return SystemState(
        reader_present=reader_present(),
        driver_installed="libfprint-2-tod1-goodix" in versions,
        tod_installed="libfprint-2-tod1" in versions,
        fprintd_installed="fprintd" in versions,
        service_active=service_active(),
        device_available=device_available(),
        package_versions=versions,
        runtime_paths_secure=runtime_paths_secure(),
        apt_protected=package_holds_active() and pin_file_current(),
    )


def state_summary(state: SystemState) -> str:
    if not state.reader_present:
        return f"Reader {USB_ID} was not detected"
    if state.ready:
        return "Reader and driver are ready"
    if not state.driver_installed:
        return "Reader detected; Goodix driver is not installed"
    if any(
        state.package_versions.get(package) != version
        for package, version in EXPECTED_TOD_VERSIONS.items()
    ):
        return "Fingerprint package versions are incompatible; repair the driver"
    if not state.runtime_paths_secure:
        return "Fingerprint driver permissions are unsafe; repair the driver"
    if not state.apt_protected:
        return "Fingerprint package upgrade protection is missing; repair the driver"
    if not state.device_available:
        return "Fingerprint packages are installed, but fprintd cannot expose the reader"
    return "Fingerprint stack needs attention"
