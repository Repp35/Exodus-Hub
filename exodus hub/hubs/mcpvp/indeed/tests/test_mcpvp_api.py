"""Reuse internal API contract checks for the MCPvP integration."""
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'indeed/tests'))
import test_api_contracts as contracts
from manifests import manifest

class MCPvPContracts(contracts.InternalAPIContracts):
    @classmethod
    def setUpClass(cls):
        original = contracts.MANIFEST
        try:
            contracts.MANIFEST = manifest(universal=False, hub_id='mcpvp')
            cls.contracts = contracts.load_contracts()
        finally:
            contracts.MANIFEST = original

    def test_manifest_has_unique_existing_modules(self):
        entries = manifest(universal=False, hub_id='mcpvp')
        self.assertEqual(len(entries), len(self.contracts))
        self.assertEqual(len(entries), len({name for name, _ in entries}))
        for _, path in entries:
            self.assertTrue((ROOT / path).is_file(), path)

if __name__ == '__main__':
    unittest.main()
