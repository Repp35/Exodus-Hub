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

    def test_internal_operation_categories(self):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary: self.skipTest('Luau required')
        helper().smoke(binary, hub_id='phantom-ball', assertions='''local policy = loaded.permissions
local spamUtils = policy.resolve("autospam", loaded).Utils
local enabledOption = loaded.utils.getConfigValue("AutoSpam")
assert(not pcall(function() spamUtils.setConfig({ AutoSpam = false }) end), "AutoSpam changed its UI option")
spamUtils.setAutoSpamActive(true)
spamUtils.setAutoSpamActive(false)
assert(loaded.utils.getConfigValue("AutoSpam") == enabledOption, "Runtime state changed UI option")
local state = { value = 7, nested = { value = 8 } }
local uiChanged = false
local newAPI = { getUnrelatedData = function() return state end,
  hideMenu = function() uiChanged = true end,
  setOption = function(patch) for key, value in pairs(patch) do state[key] = value end; return true end,
  __contract = { provides = { "getUnrelatedData", "hideMenu", "setOption" }, requires = {},
    access = { methods = { hideMenu = "ui.write", setOption = "config.write" }, scoped = { "setOption" } } } }
local reader = { __contract = { provides = {}, requires = { API = "brandNewAPI" }, requiresMethods = { API = { "getUnrelatedData" } } } }
local feature = { __config = { schema = { OwnOption = "boolean" } }, __contract = { provides = {}, requires = { API = "brandNewAPI" } } }
policy.validate("brandNewAPI", newAPI, "hubs/phantom-ball/game/brand_new_api.luau")
policy.validate("unrelatedCombat", reader, "hubs/phantom-ball/combat/unrelated.luau")
policy.validate("independentFeature", feature, "universal/independent.luau")
local modules = { brandNewAPI = newAPI, unrelatedCombat = reader, independentFeature = feature }
local api = policy.resolve("unrelatedCombat", modules).API
assert(api.getUnrelatedData().value == 7, "Generic internal reading denied")
assert(not pcall(function() api.hideMenu() end) and not uiChanged, "Unauthorized UI access")
assert(not pcall(function() api.setOption({ value = 99 }) end), "Unauthorized settings write")
assert(not pcall(function() api.getUnrelatedData().nested.value = 99 end), "Mutable internal state leaked")
assert(state.nested.value == 8)
assert(not pcall(function() api.getUnrelatedData = function() end end), "Mutable API")
assert(not pcall(rawset, api, "getUnrelatedData", function() end), "rawset bypassed API protection")
local own = policy.resolve("independentFeature", modules).API
assert(own.setOption({ OwnOption = true }))
assert(not pcall(own.setOption, { OtherOption = false }), "Other feature settings writable")
''')

    def test_game_source_compiles(self):
        binary = os.environ.get('LUAU_COMPILE_BIN') or shutil.which('luau-compile')
        if not binary: self.skipTest('Luau compiler required')
        for path in HUB.rglob('*.luau'):
            result = subprocess.run([binary, '--null', str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
