"""MM2 exports, dependencies, compilation and infrastructure initialization."""
from pathlib import Path
import importlib.util
import os
import json
import re
import shutil
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'indeed/tests'))
import test_api_contracts as contracts
from manifests import manifest

class MM2Contracts(contracts.InternalAPIContracts):
    @classmethod
    def setUpClass(cls):
        original = contracts.MANIFEST
        try:
            contracts.MANIFEST = manifest(universal=False, hub_id='mm2')
            cls.contracts = contracts.load_contracts()
        finally:
            contracts.MANIFEST = original

    def test_manifest_has_unique_existing_modules(self):
        entries = manifest(universal=False, hub_id="mm2")
        self.assertEqual(len(entries), len(self.contracts))
        self.assertEqual(len(entries), len({name for name, _ in entries}))
        for _, path in entries:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_mm2_api_loading(self):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary:
            self.skipTest('Luau required')
        spec = importlib.util.spec_from_file_location('runtime_api', ROOT / 'indeed/checks/runtime_api.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        helper.smoke(binary, hub_id='mm2')

    def test_game_source_compiles(self):
        binary = os.environ.get('LUAU_COMPILE_BIN') or shutil.which('luau-compile')
        if not binary:
            self.skipTest('Luau compiler required')
        for path in (ROOT / 'hubs/mm2').rglob('*.luau'):
            result = subprocess.run([binary, '--null', str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_game_globals(self):
        binary = os.environ.get('LUAU_ANALYZE_BIN') or shutil.which('luau-analyze')
        if not binary:
            self.skipTest('Luau analyzer required')
        paths = [ROOT / path for _, path in manifest(universal=False, hub_id='mm2') if path.startswith(('hubs/mm2/', 'ui/games/mm2/'))]
        result = subprocess.run([binary, *map(str, paths)], capture_output=True, text=True, timeout=60)
        self.assertIn(result.returncode, (0, 1), result.stdout + result.stderr)
        allowed = set(json.loads((ROOT / 'indeed/checks/roblox-globals.json').read_text()))
        unknown = [line for line in (result.stdout + result.stderr).splitlines() if (match := re.search(r"Unknown global '([^']+)'", line)) and match[1] not in allowed]
        self.assertEqual(unknown, [], '\n'.join(unknown))

if __name__ == '__main__':
    unittest.main()
