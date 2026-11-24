"""Exercise the real dumper with failing APIs and deterministic Luau tasks."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class DumperRuntime(unittest.TestCase):
    def test_retries_and_game_folder_names(self):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary:
            self.skipTest('LUAU_BIN or luau required')
        source = (ROOT / 'modules/tools/dumper.luau').read_text()
        harness = (ROOT / 'indeed/checks/dumper_retry.luau').read_text()
        code = harness.replace('local Dumper\n', 'local Dumper = (function()\n' + source + '\nend)()\n')
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / 'dumper_retry.luau'
            script.write_text(code)
            result = subprocess.run([binary, str(script)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

if __name__ == '__main__':
    unittest.main()
