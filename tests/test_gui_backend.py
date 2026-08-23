#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
import unittest

import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "lib"))

from gui_backend import SystemState, package_versions, reader_present, state_summary


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
        state = SystemState(True, True, True, True, False, {})
        self.assertTrue(state.ready)
        self.assertEqual(state_summary(state), "Reader and driver are ready")

    def test_uninstalled_summary(self):
        state = SystemState(True, False, False, True, False, {})
        self.assertFalse(state.ready)
        self.assertIn("not installed", state_summary(state))


if __name__ == "__main__":
    unittest.main()
