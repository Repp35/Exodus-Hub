"""Load real modules and resolve their APIs in Luau, without gameplay assertions."""
from pathlib import Path
import re
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

import sys
sys.path.insert(0, str(ROOT / 'indeed/checks'))
from manifests import manifest, all_entries, source_for

def smoke(binary, universal=True, hub_id=None, assertions="", bootstrap=False):
    universal = hub_id is None or hub_id == "universal"
    entries = manifest(universal, hub_id or "universal")
    code = (Path(__file__).with_name('engine_api.luau')).read_text()
    def literal(value):
        if isinstance(value, dict):
            return '{' + ','.join('[' + json.dumps(k) + ']=' + literal(v) for k, v in value.items()) + '}'
        if isinstance(value, list): return '{' + ','.join(map(literal, value)) + '}'
        return json.dumps(value, ensure_ascii=False)
    profile = {"id": hub_id or "universal"}
    if not universal:
        profile.update(json.loads((ROOT / 'hubs' / hub_id / 'hub.json').read_text()))
    code += f'\ngame.PlaceId = {next(iter(profile.get("placeIds", [0])), 0)}\n'
    code += '\nlocal profile = ' + literal(profile) + '\n'
    code += '\nlocal files = {}\n'
    for name, path in entries:
        code += f'\nif not files[{json.dumps(path)}] then files[{json.dumps(path)}] = (function()\n{(ROOT / path).read_text()}\nend)() end\n'
        code += f'loaded["{name}"] = files[{json.dumps(path)}].__bundle and files[{json.dumps(path)}].__bundle["{name}"] or files[{json.dumps(path)}]\n'
    code += '\nloaded.permissions.configure()\n'
    for name, path in entries:
        code += f'loaded.permissions.validate("{name}", loaded["{name}"], "{path}")\n'
    paths = dict(entries)
    code += '\nlocal modulePaths = ' + literal(paths) + '\n'
    code += '''
for name, module in pairs(loaded) do
  local deps = loaded.permissions.resolve(name, loaded)
  for alias, methods in pairs(module.__contract.requiresMethods or {}) do
    for _, method in ipairs(methods) do assert(type(deps[alias][method]) == "function", name .. ": " .. alias .. "." .. method) end
  end
end
local order = loaded.modulelinker.order((function()
  local entries = {}
  for name, path in pairs(modulePaths) do entries[#entries + 1] = { name = name, path = path } end
  table.sort(entries, function(a, b) return a.path < b.path or a.path == b.path and a.name < b.name end)
  return entries
end)(), loaded)
loaded.ui.setup = function() return true end
loaded.ui.create = function(options)
  assert(type(options.controls.onReload) == "function")
  assert(type(options.definition.pages) == "table")
  assert(type(options.miniScale.read) == "function" and type(options.miniScale.observe) == "function")
  return { fade = function() end, destroy = function() end }
end
local ok, bridge = loaded.bootstrap.start(loaded, order, {}, profile, {
  entryURL = function() return "https://raw.githubusercontent.com/Repp35/Exodus-Hub/main/exodus%20hub/loader.luau" end,
  reload = function() return true end, latest = function() return "revision" end,
  prepare = function() return function() end end, report = function(_, message) error(message) end,
})
assert(ok and type(bridge) == "table")
local pages = loaded.uiconfig.getPages(loaded.hubapi.getUIConfig())
local components = setmetatable({}, { __index = function() return function() end end })
assert(loaded.uipages.validate(pages, components))
local keys, actions, ids = {}, {}, {}
for _, page in ipairs(pages) do
  ids[page.id] = true
  for _, section in ipairs(page.sections) do
    for _, item in ipairs(section.components or {}) do
      if item.key then keys[item.key] = true end
      if item.action then actions[item.action] = true end
    end
  end
end
for _, key in ipairs({ "AntiAFK", "ForcePCUI", "AntiLagEnabled", "AntiLagRenderDistance", "AntiLagRemoveEffects", "UniversalFly", "UniversalInfiniteZoom", "UniversalNoclip", "UniversalJumpPowerEnabled", "UniversalJumpPower", "UniversalSpeed", "UniversalFOVEnabled", "UniversalFOV", "UniversalFullbright", "UniversalNoFog" }) do assert(keys[key], key) end
for _, action in ipairs({ "dumper", "rejoin", "serverHop", "resetCharacter", "resetSettings" }) do assert(actions[action], action) end

-- Filtering must never mutate the source definitions across UI rebuilds.
assert(#loaded.uiconfig.getPages() == #loaded.uiconfig.pages)
-- PROFILE_ASSERTIONS
local initializationErrors = loaded.utils.getDiagnostics().errors
local messages = {}
for _, item in ipairs(initializationErrors) do
  messages[#messages + 1] = tostring(item.source) .. ": " .. tostring(item.message)
end
assert(#initializationErrors == 0, "Runtime API initialization errors: " .. table.concat(messages, "\\n"))
local scope = loaded.uiruntime.scope()
assert(type(scope.destroy) == "function"); scope.destroy()
loaded.utils.stop(); loaded.utils.stop()
assert(not loaded.utils.isActive())
local state = loaded.utils.getStateSnapshot()
assert(state.connectionCounts.global == 0 and state.connectionCounts.character == 0)
print("Module exports, dependency views and infrastructure initialization OK")
'''
    code = code.replace('-- PROFILE_ASSERTIONS', assertions)
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'runtime_api.luau'
        path.write_text(code)
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout
