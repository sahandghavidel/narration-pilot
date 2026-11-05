#!/usr/bin/env python3
"""Exercise screenshot continuity with real macOS-style corner noise."""
import importlib.util
from pathlib import Path
import tempfile
import sys
sys.dont_write_bytecode = True
import unittest
from PIL import Image
spec = importlib.util.spec_from_file_location("continuity", Path(__file__).resolve().parents[1]/"guided-continuity.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ContinuityCheck(unittest.TestCase):
    def check_change(self, changes, app="Google Chrome"):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            before = Image.new("RGB", (1000, 700), (30, 30, 30))
            after = before.copy()
            for point, color in changes: after.putpixel(point, color)
            before.save(folder/"before.png"); after.save(folder/"after.png")
            return module.compare({app:str(folder/"before.png")}, {app:str(folder/"after.png")})["matched"]

    def test_composited_corner_noise(self):
        self.assertTrue(self.check_change([((0,0),(56,55,55)),((999,699),(54,56,53))]))
    def test_even_small_page_change_blocks(self):
        self.assertFalse(self.check_change([((300,300),(31,30,30))]))
    def test_larger_corner_change_blocks(self):
        self.assertFalse(self.check_change([((0,0),(100,100,100))]))
    def test_other_apps_remain_strict(self):
        self.assertFalse(self.check_change([((0,0),(31,30,30))], app="Calculator"))

if __name__ == "__main__": unittest.main()
