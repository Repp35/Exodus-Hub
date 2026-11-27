"""Check the runtime source boundary for UI construction."""
import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "checks"))
from ui_boundary import violations


class UIOwnership(unittest.TestCase):
    def test_only_ui_sources_construct_graphics(self):
        self.assertEqual(violations(), [])
