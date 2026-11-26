"""Reuse internal API contract checks for the MCPvP integration."""
from pathlib import Path
import sys
import unittest
import os
import re
import json
import shutil
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'indeed/tests'))
import test_api_contracts as contracts
from manifests import manifest

class MCPvPContracts(contracts.InternalAPIContracts):
    @classmethod
    def setUpClass(cls):
        original = contracts.MANIFEST
        try:
            contracts.MANIFEST = manifest(universal=False, hub_id='mcpvp')
            cls.contracts = contracts.load_contracts()
        finally:
            contracts.MANIFEST = original

    def test_block_units_api(self):
        runtime = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not runtime:
            self.skipTest('Luau runtime required')
        source = (ROOT / 'hubs/mcpvp/game/mcp_units.luau').read_text()
        script = 'local source = ' + json.dumps(source) + '\n' + r"""
local Vector = {}
local meta = {}
function Vector.new(x, y, z) return setmetatable({X = x, Y = y, Z = z}, meta) end
meta.__index = function(v, key)
  if key == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
end
meta.__mul = function(v, n) return Vector.new(v.X*n, v.Y*n, v.Z*n) end
meta.__div = function(v, n) return Vector.new(v.X/n, v.Y/n, v.Z/n) end
meta.__sub = function(a, b) return Vector.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
local block = 4
local environment = setmetatable({
  Vector3 = Vector,
  game = {GetService = function(_, name)
    assert(name == "ReplicatedStorage")
    return {FindFirstChild = function(_, key) assert(key == "VoxelWeapons") return {} end}
  end},
  require = function() return {Block = block} end,
}, {__index = getfenv()})
local chunk = assert(loadstring(source))
setfenv(chunk, environment)
local units = chunk()
assert(units.setup() == true)
assert(units.toWorld(0.5) == 2 and units.toBlocks(2) == 0.5)
local converted = units.toWorld(Vector.new(0.5, -1.25, 2.75))
assert(converted.X == 2 and converted.Y == -5 and converted.Z == 11)
local restored = units.toBlocks(converted)
assert(restored.X == 0.5 and restored.Y == -1.25 and restored.Z == 2.75)
assert(units.distance(Vector.new(0, 0, 0), units.offset(3, 4, 0)) == 5)
block = 3.2
assert(units.setup() == true)
assert(math.abs(units.toBlocks(units.toWorld(0.125)) - 0.125) < 1e-12)
assert(math.abs(units.toWorld(0.125) - 0.4) < 1e-12)
block = 0
assert(units.setup() == true)
assert(math.abs(units.toWorld(1) - 3.2) < 1e-12)
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'units_api.luau'
            path.write_text(script)
            result = subprocess.run([runtime, str(path)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_game_luau_syntax_and_globals(self):
        compiler = os.environ.get('LUAU_COMPILE_BIN') or shutil.which('luau-compile')
        analyzer = os.environ.get('LUAU_ANALYZE_BIN') or shutil.which('luau-analyze')
        if not compiler or not analyzer:
            self.skipTest('Luau compiler and analyzer required')
        paths = [ROOT / path for _, path in manifest(universal=False, hub_id='mcpvp')
                 if path.startswith('hubs/mcpvp/')]
        for path in paths:
            with self.subTest(path=str(path.relative_to(ROOT))):
                result = subprocess.run([compiler, '--null', str(path)], capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        allowed = set(json.loads((ROOT / 'indeed/checks/roblox-globals.json').read_text()))
        result = subprocess.run([analyzer, *map(str, paths)], capture_output=True, text=True, timeout=60)
        self.assertIn(result.returncode, (0, 1), result.stdout + result.stderr)
        errors = []
        for line in (result.stdout + result.stderr).splitlines():
            match = re.search(r"Unknown global '([^']+)'", line)
            if match and match[1] not in allowed:
                errors.append(line)
        self.assertEqual(errors, [], '\n'.join(errors))

    def test_manifest_has_unique_existing_modules(self):
        entries = manifest(universal=False, hub_id='mcpvp')
        self.assertEqual(len(entries), len(self.contracts))
        self.assertEqual(len(entries), len({name for name, _ in entries}))
        for _, path in entries:
            self.assertTrue((ROOT / path).is_file(), path)

if __name__ == '__main__':
    unittest.main()
