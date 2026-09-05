"""Read-only system state for the Goodix 550a desktop utility."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os
import pwd
import subprocess
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
    "libfprint-2-tod1": "1:1.94.7+tod1-0ubuntu5~24.04.4",
    "libfprint-2-tod1-goodix": "0.0.9",
}


@dataclass(frozen=True)
class SystemState:
    reader_present: bool
    driver_installed: bool
    tod_installed: bool
    fprintd_installed: bool
    service_active: bool
    device_available: bool
    package_versions: dict[str, str]

    @property
    def ready(self) -> bool:
        return (
            self.reader_present
            and self.driver_installed
            and self.tod_installed
            and self.fprintd_installed
            and self.device_available
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


def device_available(
    user: str,
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> bool:
    try:
        result = runner(
            ["fprintd-list", user],
            text=True,
            capture_output=True,
            check=False,
            timeout=5,
        )
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def collect_state() -> SystemState:
    versions = package_versions()
    return SystemState(
        reader_present=reader_present(),
        driver_installed="libfprint-2-tod1-goodix" in versions,
        tod_installed="libfprint-2-tod1" in versions,
        fprintd_installed="fprintd" in versions,
        service_active=service_active(),
        device_available=device_available(current_user()),
        package_versions=versions,
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
    if not state.device_available:
        return "Fingerprint packages are installed, but fprintd cannot expose the reader"
    return "Fingerprint stack needs attention"
