"""Behavior checks for replacement sessions, update policies and resource ownership."""
from pathlib import Path
import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class Behavior(unittest.TestCase):
    def run_luau(self, body, modules):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary:
            self.skipTest('Luau required')
        code = '\n'.join(f'local {name} = (function()\n{(ROOT / path).read_text()}\nend)()' for name, path in modules.items())
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'behavior.luau'
            path.write_text('local function warn() end\n' + code + '\n' + body)
            result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_resources_release_once_in_reverse_order(self):
        self.run_luau('''
local scope, calls = Lifetime.scope(), {}
local function add(n) return scope.add(function() calls[#calls + 1] = n end) end
add(1); local second = add(2); add(3)
scope.remove(second); scope.destroy(); scope.destroy()
assert(table.concat(calls, ",") == "2,3,1")
scope.add(function() calls[#calls + 1] = 4 end)
assert(calls[4] == 4)
''', {'Lifetime': 'core/lifetime.luau'})

    def test_resource_cleanup_survives_errors_and_child_removal(self):
        self.run_luau('''
local scope, calls = Lifetime.scope(), 0
scope.add(function() calls += 1 end)
local child = scope.child(); child.add(function() calls += 1 end)
child.destroy(); scope.add(function() error("expected") end)
scope.destroy(); assert(calls == 2)
''', {'Lifetime': 'core/lifetime.luau'})

    def test_configuration_registration_is_atomic(self):
        self.run_luau('''
assert(Config.register("valid", {schema = {enabled = "boolean"}, defaults = {enabled = true}}))
assert(not Config.register("invalid", {schema = {other = "boolean"}, defaults = {other = 42}}))
assert(Config.register("replacement", {schema = {other = "boolean"}, defaults = {other = false}}))
assert(not Config.validatePatch({other = 0 / 0}))
assert(Config.defaults().enabled and Config.defaults().other == false)
''', {'Config': 'core/config.luau'})

    def test_game_policies_are_optional_and_fail_closed(self):
        self.run_luau('''
local hub = Integration.__bundle.hubapi
hub.configure({}); assert(hub.canUpdate()); assert(next(hub.getMiniVisibility()) == nil)
local blocked = true
hub.configure({gameruntime = {createAPI = function() return {
  updateBlockers = {function() return blocked end},
  miniVisibility = {custom = function() return blocked end},
} end}})
assert(not hub.canUpdate()); assert(hub.getMiniVisibility().custom)
blocked = false; assert(hub.canUpdate()); assert(hub.getMiniVisibility().custom == false)
hub.configure({gameruntime = {createAPI = function() return {updateBlockers = {function() error("unavailable") end}} end}})
assert(not hub.canUpdate())
''', {'Integration': 'core/game_integration.luau'})

    def test_game_selection_prioritizes_place_and_rejects_collisions(self):
        self.run_luau('''
local profiles = {{id = "universe", universeIds = {10}}, {id = "place", placeIds = {20}}}
assert(Registry.select(profiles, 20, 10).id == "place")
assert(Registry.select(profiles, 0, 10).id == "universe")
assert(Registry.select(profiles, 0, 0).id == "universal")
assert(not pcall(Registry.merge, {{name = "base", path = "core/base.luau"}}, {{name = "base", path = "hubs/test/base.luau"}}))
assert(not pcall(Registry.merge, {}, {{name = "escape", path = "hubs/test/../escape.luau"}}))
''', {'Registry': 'hubs/registry.luau'})

    def test_update_monitor_recovers_from_transport_failure_and_cancels(self):
        # A deterministic scheduler exercises the actual update module, without network access.
        source = (ROOT / 'core/updates.luau').read_text()
        self.run_luau('''
local callbacks, errors, reloads = {}, 0, 0
local now, blocked, active = 0, true, true
local task = {delay = function(_, callback) callbacks[#callbacks + 1] = callback end}
function task.wait(dt) now += dt; if now >= 0.3 then blocked = false end end
local os = {clock = function() return now end}
local _G = {ExodusLastLoadedRevision = "old"}
local Updates = (function()
''' + source + '''
end)()
local utils = {isActive = function() return active end, getConfigValue = function() return true end, recordError = function() errors += 1 end}
Updates.setup({Utils = utils, Hub = {canUpdate = function() return not blocked end}})
assert(Updates.awaitSafe()); assert(now >= 0.7)
assert(not Updates.awaitSafe(function() return false end))
local fail = true
Updates.start({latest = function() if fail then error("offline") end; return "new" end,
  prepare = function(revision) assert(revision == "new"); return function() reloads += 1 end end})
callbacks[1](); assert(errors == 1 and reloads == 0 and not Updates.getStatus().checking)
fail = false; callbacks[2](); assert(reloads == 1 and _G.ExodusRequestedRevision.automatic)
Updates.teardown(); callbacks[3](); assert(reloads == 1)
''', {})

    def test_anti_lag_applies_a_scene_in_one_batch_and_restores_it(self):
        source = (ROOT / 'universal/anti_lag/properties.luau').read_text()
        self.run_luau('''
local function signal()
  local callbacks = {}
  return {Connect = function(_, callback)
    callbacks[#callbacks + 1] = callback
    return {Disconnect = function() end}
  end}
end
local function node(class, parent)
  local object = {ClassName = class, Parent = parent, children = {}, DescendantAdded = signal(), DescendantRemoving = signal(), Changed = signal()}
  function object:IsA(kind) return kind == self.ClassName end
  function object:GetChildren() return self.children end
  function object:IsDescendantOf(root)
    local parent = self.Parent
    while parent do if parent == root then return true end; parent = parent.Parent end
    return false
  end
  if parent then parent.children[#parent.children + 1] = object end
  return object
end
local task = {defer = function(callback) callback() end, delay = function() end}
local os = {clock = function() return 0 end}
local Color3 = {new = function() return {} end}
local NumberSequence, NumberRange = {new = function() return {} end}, {new = function() return {} end}
local Enum = {LightingStyle = {Soft = 1}}
local Properties = (function()
''' + source + '''
end)()
local world, lighting = node("Workspace"), node("Lighting")
lighting.GlobalShadows = true
local parts = {}
for index = 1, 1000 do
  parts[index] = node("BasePart", world); parts[index].CastShadow = true
end
local emitter = node("ParticleEmitter", world); emitter.Enabled = true
local heartbeat = {Wait = function() error("Small initial scene should not wait for another frame") end}
local controller = Properties.create({Workspace = world, Lighting = lighting,
  RunService = {Heartbeat = heartbeat}, CollectionService = {GetInstanceAddedSignal = signal, GetInstanceRemovedSignal = signal}},
  {StartEnabled = false, Shadows = true, Particles = true, BudgetMs = 1.5, MaxItemsPerFrame = 160, ReapplyInterval = 0.25})
controller:SetEnabled(true)
assert(not lighting.GlobalShadows and not emitter.Enabled)
for _, part in ipairs(parts) do assert(not part.CastShadow) end
controller:Destroy()
assert(lighting.GlobalShadows and emitter.Enabled and not controller:GetStatus().Alive)
for _, part in ipairs(parts) do assert(part.CastShadow) end
''', {})

    def test_information_page_is_readonly_and_versions_are_independent(self):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary: self.skipTest('Luau required')
        spec = importlib.util.spec_from_file_location('runtime_information', ROOT / 'indeed/checks/runtime_api.py')
        helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
        helper.smoke(binary, hub_id='phantom-ball', assertions='''
assert(loaded.utils.version() == "2.0.0")
assert(loaded.gamecontext.getProfile().version == "3.3.0")
local page
for _, value in ipairs(pages) do if value.id == "information" then page = value end end
assert(page and page.utility)
local count = 0
for _, section in ipairs(page.sections) do
  for _, item in ipairs(section.components) do
    assert(item.kind == "readout" and item.info and not item.key and not item.action)
    count += 1
  end
end
assert(count >= 20)
assert(keys.AutoExecuteOnJoin and keys.AutoExecuteAllGames and keys.AutoExecute)
local snapshot = loaded.permissions.resolve("ui", loaded).Information.snapshot()
assert(snapshot.country == "Indisponível" and snapshot.city == "Indisponível")
assert(not pcall(function() snapshot.hubVersion = "wrong" end))
''')

    def test_bootstrap_initializes_and_stops_both_profiles(self):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary:
            self.skipTest('Luau required')
        spec = importlib.util.spec_from_file_location('runtime_behavior', ROOT / 'indeed/checks/runtime_api.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        for hub in ('universal', 'phantom-ball'):
            with self.subTest(hub=hub):
                helper.smoke(binary, hub_id=hub, bootstrap=True)


if __name__ == '__main__':
    unittest.main()
