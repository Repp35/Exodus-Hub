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
        for path in [ROOT / 'loader.luau', *sorted((ROOT / 'hubs').glob('*.luau')), *[p for folder in ('core','universal','ui') for p in sorted((ROOT / folder).rglob('*.luau'))], *sorted((ROOT / 'indeed/checks').glob('*.luau')), *sorted((ROOT / 'indeed/diagnostics').glob('*.luau'))]:
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
        paths = [ROOT / 'loader.luau', *[p for folder in ('core','universal','ui') for p in sorted((ROOT / folder).rglob('*.luau'))], *sorted((ROOT / 'hubs').glob('*.luau')), *sorted((ROOT / 'indeed/diagnostics').glob('*.luau'))]
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
        helper.smoke(binary, universal=True, assertions="""
local originalOffset = UDim2.fromOffset
UDim2.fromOffset = function(x, y) return { X = { Offset = x }, Y = { Offset = y } } end
local textService = game:GetService("TextService")
function textService:GetTextSize() return { X = 100 } end
local headerScope = loaded.lifetime.scope()
local function instance(_, properties)
  properties.GetChildren = function() return {} end
  properties.GetPropertyChangedSignal = function() return services.RunService.Heartbeat end
  properties.ChildAdded, properties.ChildRemoved = services.RunService.Heartbeat, services.RunService.Heartbeat
  return properties
end
for _, brand in ipairs({ { name = "Standalone", author = "" }, { name = "Exodus", author = "Author", version = "3.0.0" } }) do
  local header = loaded.uiheader.create({ theme = loaded.uitheme.tokens, inst = instance, brand = brand, scope = headerScope }, {})
  assert(type(header.refresh) == "function" and type(header.setIcon) == "function")
end
headerScope.destroy()
UDim2.fromOffset = originalOffset
""")
        for info in sorted((ROOT / 'hubs').glob('*/hub.json')):
            with self.subTest(hub=info.parent.name):
                helper.smoke(binary, hub_id=info.parent.name)

    def test_option_scope_and_schema_api(self):
        binary = self.binary('LUAU_BIN', 'luau')
        spec = importlib.util.spec_from_file_location('runtime_api', CHECKS / 'runtime_api.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        helper.smoke(binary, assertions="""
assert(loaded.options.describe("UniversalFly").scope == "hub")
assert(not loaded.config.isPersistentKey("UniversalFly"))
assert(loaded.config.isPersistentKey("UniversalFlySpeed"))
assert(loaded.config.validatePatch({ AntiLagKeepNear = 128 }))
assert(not loaded.config.validatePatch({ AntiLagKeepNear = 0 }))
assert(not loaded.config.validatePatch({ AntiLagRenderDistance = math.huge }))
assert(loaded.config.defaults().MiniUIScale == 1)
assert(loaded.config.defaults().DesktopNotifications == true)
assert(loaded.config.defaults().DesktopShortcutNotifications == true)
assert(loaded.config.defaults().CornerNotifications == true)
assert(loaded.config.validatePatch({ DesktopNotifications = false, CornerNotifications = true }))
assert(loaded.config.validatePatch({ DesktopNotifications = true, CornerNotifications = false }))
assert(loaded.config.isPersistentKey("MiniUIScale"))
assert(loaded.config.validatePatch({ MiniUIScale = 1.5 }))
assert(not loaded.config.validatePatch({ MiniUIScale = 0 }))
local saved = { MiniUIScale = 1.5, AntiLagFloorCull = true }
assert(loaded.hubapi.migrateConfig(saved))
assert(saved.MiniUIScale == 1.5 and saved.AntiLagFloorCull == nil)
assert(type(loaded.options.observe("AntiLagEnabled", function() end).Disconnect) == "function")
assert(not pcall(loaded.options.get, "unknown"))
loaded.config.reset()
assert(loaded.config.register("empty", { schema = {}, defaults = {} }))
assert(not loaded.config.register("empty", { schema = {}, defaults = {} }))
loaded.config.reset()
assert(loaded.config.register("empty", { schema = {}, defaults = {} }))
""")

    def test_universal_property_and_scheduler_api(self):
        binary = self.binary('LUAU_BIN', 'luau')
        spec = importlib.util.spec_from_file_location('runtime_api', CHECKS / 'runtime_api.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        helper.smoke(binary, assertions="""
local original = { Value = 70, Flag = true }
local target = original
local desired = { Value = 90, Flag = false }
local binding = loaded.propertybinding.create(function() return target end, function() return desired end)
binding.update()
assert(original.Value == 90 and original.Flag == false)
target = { Value = 80 }
binding.update()
assert(original.Value == 70 and original.Flag == true and target.Value == 90)
target.Value = 85
binding.update()
binding.restore()
assert(target.Value == 80)
binding.restore()
local sharedTarget = { Value = 12, Flag = true }
local low, high = {}, {}
assert(loaded.propertybinding.apply(low, sharedTarget, "Value", 20, 0))
assert(loaded.propertybinding.apply(high, sharedTarget, "Value", 40, 20))
assert(sharedTarget.Value == 40)
assert(loaded.propertybinding.release(low, sharedTarget, "Value"))
assert(sharedTarget.Value == 40)
assert(loaded.propertybinding.release(high, sharedTarget, "Value"))
assert(sharedTarget.Value == 12)
assert(loaded.propertybinding.apply(low, sharedTarget, "Flag", false))
assert(sharedTarget.Flag == false)
assert(loaded.propertybinding.release(low, sharedTarget, "Flag"))
assert(sharedTarget.Flag == true)
local scope = loaded.lifetime.scope()
local calls = 0
loaded.universalcontroller.connectPhysics(scope, function() calls += 1 end)
services.RunService.PreSimulation:Fire(1 / 60)
services.RunService.PostSimulation:Fire(1 / 60)
assert(calls == 2)
scope.destroy()
services.RunService.PreSimulation:Fire(1 / 60)
services.RunService.PostSimulation:Fire(1 / 60)
assert(calls == 2)
""")


    def test_universal_cleanup_api(self):
        binary = self.binary('LUAU_BIN', 'luau')
        spec = importlib.util.spec_from_file_location('runtime_api', CHECKS / 'runtime_api.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        helper.smoke(binary, assertions="""
local player = services.Players.LocalPlayer
player.CameraMinZoomDistance, player.CameraMaxZoomDistance = 0.5, 18
assert(loaded.infinitezoom.setEnabled(true))
player.CameraMaxZoomDistance = 600000
services.RunService.PreSimulation:Fire(1 / 60)
assert(loaded.infinitezoom.setEnabled(false))
assert(player.CameraMaxZoomDistance == 18)
services.RunService.PreSimulation:Fire(1 / 60)
services.RunService.PostSimulation:Fire(1 / 60)
assert(player.CameraMaxZoomDistance == 18)
player.CameraMaxZoomDistance = 32
assert(loaded.infinitezoom.setEnabled(true))
assert(loaded.infinitezoom.setEnabled(false))
assert(player.CameraMaxZoomDistance == 32)

local stored = { Limit = 24 }
local coerced = setmetatable({}, {
  __index = function(_, key) return stored[key] end,
  __newindex = function(_, key, value) stored[key] = math.min(value, 1000) end,
})
local binding = loaded.propertybinding.create(function() return coerced end, function() return { Limit = 1000000 } end)
binding.update(); binding.update()
assert(stored.Limit == 1000)
binding.restore()
assert(stored.Limit == 24)

local world = services.Workspace
world.CurrentCamera = { FieldOfView = 76 }
assert(loaded.fov.setValue(100))
assert(loaded.fov.setEnabled(true))
assert(world.CurrentCamera.FieldOfView == 100)
world.CurrentCamera.FieldOfView = 84
services.RunService.PostSimulation:Fire(1 / 60)
assert(loaded.fov.setEnabled(false))
assert(world.CurrentCamera.FieldOfView == 76)
world.Gravity = 165
assert(loaded.gravity.setValue(80))
assert(loaded.gravity.setEnabled(true))
assert(world.Gravity == 80)
assert(loaded.gravity.setEnabled(false))
assert(world.Gravity == 165)

local lighting = game:GetService("Lighting")
lighting.Brightness, lighting.ClockTime, lighting.GlobalShadows = 0.6, 7, true
assert(loaded.fullbright.setEnabled(true))
assert(lighting.GlobalShadows == false)
assert(loaded.fullbright.setEnabled(false))
assert(lighting.Brightness == 0.6 and lighting.ClockTime == 7 and lighting.GlobalShadows == true)
lighting.FogStart, lighting.FogEnd = 15, 280
assert(loaded.nofog.setEnabled(true))
local atmosphere = { Parent = lighting, Density = 0.35, Haze = 1.2, IsA = function(_, name) return name == "Atmosphere" end }
lighting.ChildAdded:Fire(atmosphere)
assert(atmosphere.Density == 0 and atmosphere.Haze == 0)
assert(loaded.nofog.setEnabled(false))
assert(lighting.FogStart == 15 and lighting.FogEnd == 280)
assert(atmosphere.Density == 0.35 and atmosphere.Haze == 1.2)

local humanoid = { Parent = true, Health = 100, WalkSpeed = 16, JumpPower = 50, UseJumpPower = true, JumpHeight = 7 }
local character = { FindFirstChildOfClass = function(_, name) return name == "Humanoid" and humanoid or nil end }
player.Character = character
assert(loaded.speed.setValue(30))
assert(loaded.speed.setEnabled(true))
assert(humanoid.WalkSpeed == 30)
assert(loaded.speed.setEnabled(false))
assert(humanoid.WalkSpeed == 16)
assert(loaded.jumppower.setValue(100))
assert(loaded.jumppower.setEnabled(true))
assert(humanoid.JumpPower == 100)
assert(loaded.jumppower.setEnabled(false))
assert(humanoid.JumpPower == 50 and humanoid.UseJumpPower == true)
player.Character = nil
services.RunService.PreSimulation:Fire(1 / 60)
services.RunService.PostSimulation:Fire(1 / 60)
assert(world.CurrentCamera.FieldOfView == 76 and world.Gravity == 165)
assert(lighting.FogEnd == 280 and player.CameraMaxZoomDistance == 32)
""")

if __name__ == '__main__': unittest.main()
