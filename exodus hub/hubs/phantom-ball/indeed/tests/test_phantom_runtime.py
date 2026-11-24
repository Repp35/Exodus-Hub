from pathlib import Path
import importlib.util
import json
import os
import shutil
import subprocess
import unittest
ROOT = Path(__file__).resolve().parents[4]
HUB = ROOT / 'hubs/phantom-ball'

def helper():
    spec = importlib.util.spec_from_file_location('runtime_api', ROOT / 'indeed/checks/runtime_api.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module

class PhantomRuntime(unittest.TestCase):
    def test_optional_permissions(self):
        if not json.loads((HUB / 'hub.json').read_text()).get('checkPermissions', False):
            self.skipTest('Permissions check not requested by this game')
        result = subprocess.run(['python3', str(ROOT / 'indeed/tools/check_permissions.py'), '--hub', 'phantom-ball'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_phantom_api_and_ui_configuration(self):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary: self.skipTest('Luau required')
        helper().smoke(binary, hub_id='phantom-ball', assertions='''assert(type(loaded.gameinfo.getGameContext()) == "table")
loaded.combatloop.pulse(1 / 60)
assert(bridge.mode ~= "universal")
assert(keys.AutoParry and keys.AntiLagRemoveSwordSounds and ids.assists)
assert(loaded.autojump and loaded.camera)
assert(#loaded.uipages.forGame(loaded.uiconfig.getPages(loaded.hubapi.getUIConfig()), true) == 8)
''')

    def test_game_source_compiles(self):
        binary = os.environ.get('LUAU_COMPILE_BIN') or shutil.which('luau-compile')
        if not binary: self.skipTest('Luau compiler required')
        for path in HUB.rglob('*.luau'):
            result = subprocess.run([binary, '--null', str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
