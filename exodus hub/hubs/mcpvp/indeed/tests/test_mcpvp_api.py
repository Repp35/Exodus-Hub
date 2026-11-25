"""Reuse internal API contract checks for the MCPvP integration."""
from pathlib import Path
import sys
import unittest
import os
import re
import json
import shutil
import subprocess
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

    def test_game_luau_syntax_and_globals(self):
        compiler = os.environ.get('LUAU_COMPILE_BIN') or shutil.which('luau-compile')
        analyzer = os.environ.get('LUAU_ANALYZE_BIN') or shutil.which('luau-analyze')
        if not compiler or not analyzer:
            self.skipTest('Luau compiler and analyzer required')
        paths = [ROOT / path for _, path in manifest(universal=False, hub_id='mcpvp')
                 if path.startswith('hubs/mcpvp/')]
        for path in paths:
            with self.subTest(path=str(path.relative_to(ROOT))):
                result = subprocess.run([compiler, '--null', str(path)], capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        allowed = set(json.loads((ROOT / 'indeed/checks/roblox-globals.json').read_text()))
        result = subprocess.run([analyzer, *map(str, paths)], capture_output=True, text=True, timeout=60)
        self.assertIn(result.returncode, (0, 1), result.stdout + result.stderr)
        errors = []
        for line in (result.stdout + result.stderr).splitlines():
            match = re.search(r"Unknown global '([^']+)'", line)
            if match and match[1] not in allowed:
                errors.append(line)
        self.assertEqual(errors, [], '\n'.join(errors))

    def test_manifest_has_unique_existing_modules(self):
        entries = manifest(universal=False, hub_id='mcpvp')
        self.assertEqual(len(entries), len(self.contracts))
        self.assertEqual(len(entries), len({name for name, _ in entries}))
        for _, path in entries:
            self.assertTrue((ROOT / path).is_file(), path)

if __name__ == '__main__':
    unittest.main()
