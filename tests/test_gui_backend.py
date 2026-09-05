#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
import unittest

import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "lib"))

from gui_backend import (
    EXPECTED_TOD_VERSIONS,
    SystemState,
    device_available,
    package_versions,
    reader_present,
    state_summary,
)


class BackendTests(unittest.TestCase):
    def test_reader_present(self):
        with tempfile.TemporaryDirectory() as temp:
            device = Path(temp) / "3-3"
            device.mkdir()
            (device / "idVendor").write_text("27C6\n", encoding="ascii")
            (device / "idProduct").write_text("550A\n", encoding="ascii")
            self.assertTrue(reader_present(Path(temp)))

    def test_reader_absent(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertFalse(reader_present(Path(temp)))

    def test_package_parser_ignores_missing_packages(self):
        def runner(command, **_kwargs):
            if command[-1] == "fprintd":
                return subprocess.CompletedProcess(command, 0, "installed\t1.2.3", "")
            return subprocess.CompletedProcess(command, 1, "", "missing")

        self.assertEqual(package_versions(runner), {"fprintd": "1.2.3"})

    def test_ready_summary(self):
        state = SystemState(True, True, True, True, False, True, EXPECTED_TOD_VERSIONS)
        self.assertTrue(state.ready)
        self.assertEqual(state_summary(state), "Reader and driver are ready")

    def test_uninstalled_summary(self):
        state = SystemState(True, False, False, True, False, False, {})
        self.assertFalse(state.ready)
        self.assertIn("not installed", state_summary(state))

    def test_incompatible_versions_are_not_ready(self):
        versions = dict(EXPECTED_TOD_VERSIONS)
        versions["libfprint-2-2"] = "1:1.94.10-1"
        state = SystemState(True, True, True, True, True, True, versions)
        self.assertFalse(state.ready)
        self.assertIn("incompatible", state_summary(state))

    def test_unavailable_device_is_not_ready(self):
        state = SystemState(True, True, True, True, False, False, EXPECTED_TOD_VERSIONS)
        self.assertFalse(state.ready)
        self.assertIn("cannot expose", state_summary(state))

    def test_device_available_uses_fprintd(self):
        def runner(command, **_kwargs):
            return subprocess.CompletedProcess(command, 0, "found", "")

        self.assertTrue(device_available("test-user", runner))


if __name__ == "__main__":
    unittest.main()
