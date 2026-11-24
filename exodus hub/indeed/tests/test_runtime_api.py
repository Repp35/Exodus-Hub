"""Basic project health: permissions, actual Luau syntax, exports and API wiring."""
from pathlib import Path
import importlib.util
import os
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECKS = ROOT / 'indeed/checks'

class RuntimeAPI(unittest.TestCase):
    def test_permissions(self):
        result = subprocess.run(['python3', str(ROOT / 'indeed/tools/check_permissions.py')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def binary(self, env, name):
        binary = os.environ.get(env) or shutil.which(name)
        if not binary:
            self.skipTest(f'{env} or {name} required; CI installs Luau 0.748')
        return binary

    def test_actual_luau_compilation(self):
        binary = self.binary('LUAU_COMPILE_BIN', 'luau-compile')
        for path in sorted(ROOT.rglob('*.luau')):
            if 'legacy_tests' in path.parts:
                continue
            with self.subTest(path=str(path.relative_to(ROOT))):
                result = subprocess.run([binary, '--null', str(path)], capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_no_undeclared_globals(self):
        import json
        binary = self.binary('LUAU_ANALYZE_BIN', 'luau-analyze')
        allowed = set(json.loads((CHECKS / 'roblox-globals.json').read_text()))
        paths = [ROOT / 'loader.luau', *sorted((ROOT / 'modules').rglob('*.luau')), *sorted((ROOT / 'indeed/diagnostics').glob('*.luau'))]
        result = subprocess.run([binary, *map(str, paths)], capture_output=True, text=True, timeout=60)
        self.assertIn(result.returncode, (0, 1), result.stdout + result.stderr)
        errors = []
        for line in (result.stdout + result.stderr).splitlines():
            match = re.search(r"Unknown global '([^']+)'", line)
            if match and match[1] not in allowed:
                errors.append(line)
        self.assertEqual(errors, [], '\n'.join(errors))

    def test_actual_luau_api_loading(self):
        binary = self.binary('LUAU_BIN', 'luau')
        spec = importlib.util.spec_from_file_location('runtime_api', CHECKS / 'runtime_api.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        helper.smoke(binary)
        helper.smoke(binary, universal=True)

if __name__ == '__main__': unittest.main()
