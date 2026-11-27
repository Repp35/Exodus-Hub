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
        result = subprocess.run(['python3', str(ROOT / 'indeed/tools/check_permissions.py'), '--hub', 'universal'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


    def binary(self, env, name):
        binary = os.environ.get(env) or shutil.which(name)
        if not binary:
            self.skipTest(f'{env} or {name} required; CI installs Luau 0.748')
        return binary

    def test_actual_luau_compilation(self):
        binary = self.binary('LUAU_COMPILE_BIN', 'luau-compile')
        for path in [ROOT / 'loader.luau', ROOT / 'hubs/registry.luau', ROOT / 'hubs/catalog.luau', *[p for folder in ('core','universal','ui') for p in sorted((ROOT / folder).rglob('*.luau'))], *sorted((ROOT / 'indeed/checks').glob('*.luau')), *sorted((ROOT / 'indeed/diagnostics').glob('*.luau'))]:
            with self.subTest(path=str(path.relative_to(ROOT))):
                result = subprocess.run([binary, '--null', str(path)], capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                if re.search(r'^--!native\s*$', path.read_text(), re.MULTILINE):
                    native = subprocess.run([binary, '--codegennull', str(path)], capture_output=True, text=True, timeout=30)
                    self.assertEqual(native.returncode, 0, native.stdout + native.stderr)

    def test_strict_modules_pass_full_analysis(self):
        binary = self.binary('LUAU_ANALYZE_BIN', 'luau-analyze')
        paths = [path for path in ROOT.rglob('*.luau')
                 if 'indeed' not in path.relative_to(ROOT).parts
                 and re.search(r'^--!strict\s*$', path.read_text(), re.MULTILINE)]
        result = subprocess.run([binary, *map(str, paths)], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_no_undeclared_globals(self):
        import json
        binary = self.binary('LUAU_ANALYZE_BIN', 'luau-analyze')
        allowed = set(json.loads((CHECKS / 'roblox-globals.json').read_text()))
        paths = [ROOT / 'loader.luau', *[p for folder in ('core','universal','ui') for p in sorted((ROOT / folder).rglob('*.luau'))], ROOT / 'hubs/registry.luau', ROOT / 'hubs/catalog.luau', *sorted((ROOT / 'indeed/diagnostics').glob('*.luau'))]
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
        helper.smoke(binary, universal=True)

if __name__ == '__main__': unittest.main()
