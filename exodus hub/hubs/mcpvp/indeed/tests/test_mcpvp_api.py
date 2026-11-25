"""Essential syntax, exports, dependency and configuration contracts for MCPVP."""
from pathlib import Path
import importlib.util
import json
import os
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[4]
HUB = ROOT / 'hubs/mcpvp'

class MCPVPAPI(unittest.TestCase):
    def binary(self, env, name):
        binary = os.environ.get(env) or shutil.which(name)
        if not binary:
            self.skipTest(f'{name} required')
        return binary

    def test_compilation_and_declared_globals(self):
        compiler = self.binary('LUAU_COMPILE_BIN', 'luau-compile')
        analyzer = self.binary('LUAU_ANALYZE_BIN', 'luau-analyze')
        paths = list(HUB.rglob('*.luau'))
        for path in paths:
            result = subprocess.run([compiler, '--null', str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        allowed = set(json.loads((ROOT / 'indeed/checks/roblox-globals.json').read_text()))
        result = subprocess.run([analyzer, *map(str, paths)], capture_output=True, text=True, timeout=30)
        errors = []
        for line in (result.stdout + result.stderr).splitlines():
            match = re.search(r"Unknown global '([^']+)'", line)
            if match and match[1] not in allowed:
                errors.append(line)
        self.assertEqual(errors, [])

    def test_exports_dependencies_and_ui_config(self):
        spec = importlib.util.spec_from_file_location('runtime_api', ROOT / 'indeed/checks/runtime_api.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        helper.smoke(self.binary('LUAU_BIN', 'luau'), hub_id='mcpvp', assertions='''
assert(loaded.gamecontext.getProfile().id == "mcpvp")
for name, module in pairs(loaded) do
  if name:sub(1, 3) == "mcp" then
    for member, value in pairs(module) do
      if type(value) == "function" then
        assert(table.find(module.__contract.provides, member), name .. ": undeclared API export " .. member)
      end
    end
  end
end
local config = loaded.config.getRegistry().mcpoptions
for _, group in ipairs(loaded.mcpoptions.groups) do
  for _, option in ipairs(group.items) do
    assert(config.schema[option.key] == "boolean", option.key)
    assert(config.defaults[option.key] ~= nil, option.key)
  end
end
for key in pairs(loaded.mcpoptions.tuning) do
  assert(config.schema[key] == nil, "Internal tuning leaked into user settings: " .. key)
end
local api = loaded.gameruntime.createAPI(loaded)
assert(type(api.updateBlockers[1]) == "function")
assert(type(api.readouts[1].read()) == "string")
''')
