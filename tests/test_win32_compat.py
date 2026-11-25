import os
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "viewer"))

import live_monitor


class TestOpenFoamWin32Compat(unittest.TestCase):
    def test_find_windows_paraview_scans_program_files(self):
        with mock.patch("live_monitor.shutil.which", return_value=None), \
             mock.patch.dict(os.environ, {"ProgramFiles": "C:\\Program Files"}), \
             mock.patch("live_monitor.glob.glob", return_value=["C:\\Program Files\\ParaView 5.13\\bin\\paraview.exe"]), \
             mock.patch("live_monitor.os.path.isfile", return_value=True):
            found = live_monitor._find_windows_paraview("paraview.exe")
            self.assertEqual(found, "C:\\Program Files\\ParaView 5.13\\bin\\paraview.exe")

    def test_scripts_and_ps1_exist(self):
        self.assertTrue((ROOT / "openfoam.ps1").is_file())
        self.assertTrue((ROOT / "install_win.ps1").is_file())
        src = (ROOT / "viewer" / "live_monitor.py").read_text(encoding="utf-8")
        compile(src, str(ROOT / "viewer" / "live_monitor.py"), "exec")


if __name__ == "__main__":
    unittest.main()
