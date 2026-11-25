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
    permissions_enabled = not universal and profile.get("permissions", True) is not False
    if not permissions_enabled:
        loader = (ROOT / 'loader.luau').read_text()
        start = loader.index('local function basicLinker()')
        end = loader.index('local function loadModules(', start)
        code += '\n' + loader[start:end] + '\nloaded.permissions = basicLinker()\nloaded.permissions.__contract = { requires = {}, provides = { "validate", "resolve" } }\n'
    if permissions_enabled:
        code += '\nloaded.permissions.configure(profile.permissionPolicy)\n'
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
loaded.gamecontext.configure(profile)
loaded.hubapi.configure(loaded)
assert(loaded.utils.configure(loaded.permissions.resolve("utils", loaded)))
loaded.utils.start()
for name, module in pairs(loaded) do
  if module.__config then assert(loaded.config.register(name, module.__config), name) end
end
loaded.utils.setConfigModule(loaded.config)
loaded.utils.setConfig(loaded.config.defaults())
loaded.utils.loadConfig()
local initialized, order = {}, {}
local function initialize(name)
  if initialized[name] then return end
  initialized[name] = true
  local module = loaded[name]
  for _, dependency in pairs(module.__contract.requires or {}) do initialize(dependency) end
  if name ~= "utils" and name ~= "config" and name ~= "uiconfig" and name ~= "permissions" and name ~= "ui" and loaded.gamecontext.supportsModule(name, modulePaths[name]) then
    local deps = loaded.permissions.resolve(name, loaded)
    if name == "character" then deps.characterBinds = {} end
    local ok, detail = module.setup(deps)
    assert(ok == true, name .. ": " .. tostring(detail))
    order[#order + 1] = name
  end
end
for name in pairs(loaded) do if name ~= "character" then initialize(name) end end
initialize("character")
local bridge = loaded.runtime.bind(loaded, order, services.HttpService, function(_, message) error(message) end)
assert(type(bridge) == "table", "Runtime API binding failed")
local pages = loaded.uipages.forGame(loaded.uiconfig.getPages(loaded.hubapi.getUIConfig()), loaded.hubapi.getUIConfig().combatUI == true)
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
for _, key in ipairs({ "AntiAFK", "ForcePCUI", "AntiLagEnabled", "AntiLagRenderDistance", "AntiLagRemoveEffects", "UniversalFly", "UniversalInfiniteZoom", "UniversalNoclip" }) do assert(keys[key], key) end
for _, action in ipairs({ "dumper", "rejoin", "serverHop", "resetCharacter", "resetSettings" }) do assert(actions[action], action) end

-- Filtering must never mutate the source definitions across UI rebuilds.
assert(#loaded.uipages.forGame(loaded.uiconfig.pages, true) == #loaded.uiconfig.pages)
-- PROFILE_ASSERTIONS
assert(#loaded.utils.getDiagnostics().errors == 0, "Runtime API initialization errors")
local scope = loaded.uiruntime.scope()
assert(type(scope.destroy) == "function"); scope.destroy()
for index = #order, 1, -1 do
  local module = loaded[order[index]]
  if module.teardown then module.teardown() end
end
loaded.utils.stop()
print("Module exports, dependency views and infrastructure initialization OK")
'''
    if bootstrap:
        start = code.rindex('loaded.gamecontext.configure(profile)')
        end = code.index('local pages = ', start)
        code = code[:start] + '''
local order, visited = {}, {}
local function visit(name)
  if visited[name] or name == "permissions" or name == "ui" then return end
  visited[name] = true
  for _, dependency in pairs(loaded[name].__contract.requires or {}) do visit(dependency) end
  if name ~= "character" then order[#order + 1] = name end
end
for name in pairs(loaded) do visit(name) end
order[#order + 1] = "character"
loaded.ui.setup = function(deps) assert(type(deps.Controls.onReload) == "function"); return true end
local ok, runtime = loaded.bootstrap.start(loaded, order, {}, profile, {
  entryURL = function() return "https://raw.githubusercontent.com/Repp35/Exodus-Hub/main/exodus%20hub/loader.luau" end,
  reload = function() return true end, latest = function() return "revision" end,
  prepare = function() return function() end end, report = function(_, message) error(message) end,
})
assert(ok and type(runtime) == "table")
''' + code[end:]
        start = code.index('for index = #order, 1, -1 do')
        end = code.index('print("Module exports', start)
        code = code[:start] + '''
loaded.utils.stop(); loaded.utils.stop()
assert(not loaded.utils.isActive())
local state = loaded.utils.getStateSnapshot()
assert(state.connectionCounts.global == 0 and state.connectionCounts.character == 0)
''' + code[end:]
    code = code.replace('-- PROFILE_ASSERTIONS', assertions)
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'runtime_api.luau'
        path.write_text(code)
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout
