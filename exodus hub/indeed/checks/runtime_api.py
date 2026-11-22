"""Load real modules and resolve their APIs in Luau, without gameplay assertions."""
from pathlib import Path
import re
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def manifest():
    return re.findall(r'\{\s*name\s*=\s*"(\w+)",\s*path\s*=\s*"([^"]+)"\s*\}', (ROOT / 'loader.luau').read_text())

def smoke(binary):
    entries = manifest()
    code = (Path(__file__).with_name('engine_api.luau')).read_text()
    policy_text = re.search(r'local POLICY_JSON\s*=\s*\[=\[(.*?)\]=\]', (ROOT / 'modules/core/permissions.luau').read_text(), re.S)[1]
    def literal(value):
        if isinstance(value, dict):
            return '{' + ','.join('[' + json.dumps(k) + ']=' + literal(v) for k, v in value.items()) + '}'
        if isinstance(value, list): return '{' + ','.join(map(literal, value)) + '}'
        return json.dumps(value)
    code += '\nservices.HttpService = { JSONDecode = function(_, text) assert(text == [=[' + policy_text + ']=]); return ' + literal(json.loads(policy_text)) + ' end }\n'
    for name, path in entries:
        code += f'\nloaded["{name}"] = (function()\n{(ROOT / path).read_text()}\nend)()\n'
    for name, path in entries:
        code += f'loaded.permissions.validate("{name}", loaded["{name}"], "{path}")\n'
    code += '''
for name, module in pairs(loaded) do
  local deps = loaded.permissions.resolve(name, loaded)
  for alias, methods in pairs(module.__contract.requiresMethods or {}) do
    for _, method in ipairs(methods) do assert(type(deps[alias][method]) == "function", name .. ": " .. alias .. "." .. method) end
  end
end
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
  if name ~= "utils" and name ~= "config" and name ~= "uiconfig" and name ~= "permissions" and name ~= "ui" then
    local deps = loaded.permissions.resolve(name, loaded)
    if name == "character" then deps.characterBinds = {} end
    local ok, detail = module.setup(deps)
    assert(ok == true, name .. ": " .. tostring(detail))
    order[#order + 1] = name
  end
end
for name in pairs(loaded) do initialize(name) end
assert(type(loaded.gameinfo.getGameContext()) == "table")
local bridge = loaded.runtime.bind(loaded, order, services.HttpService, function(_, message) error(message) end)
assert(type(bridge) == "table", "Runtime API binding failed")
loaded.combatloop.pulse(1 / 60)
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
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'runtime_api.luau'
        path.write_text(code)
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout
