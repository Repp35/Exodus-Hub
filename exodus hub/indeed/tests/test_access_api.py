"""Access-policy and module-linker API checks using the runtime's actual modules."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class AccessAPI(unittest.TestCase):
    def test_access_policy_and_manifest(self):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary:
            self.skipTest('Luau required')
        registry = (ROOT / 'hubs/registry.luau').read_text()
        access = (ROOT / 'hubs/access.luau').read_text()
        linker = (ROOT / 'core/module_linker.luau').read_text()
        source = f'local registry = (function()\n{registry}\nend)()\n'
        source += f'local access = (function()\n{access}\nend)()\n'
        source += f'local linker = (function()\n{linker}\nend)()\n'
        common_catalog = (ROOT / 'core/catalog.luau').read_text()
        hub_catalog = (ROOT / 'hubs/catalog.luau').read_text()
        source += f'local shared = (function()\n{common_catalog}\nend)()\n'
        source += f'local catalog = (function()\n{hub_catalog}\nend)()\n'
        source += 'for _, profile in ipairs(catalog) do assert(#registry.manifest(shared, profile) > #shared) end\n'
        source += 'assert(not pcall(registry.merge, {}, {{name="invalid",path="ui/games/mm2/../core.luau"}}))\n'
        source += '''
local profiles = {
  { id = "mcpvp", title = "MCPvP", placeIds = { 10 }, universeIds = { 20 } },
  { id = "phantom-ball", title = "Phantom Ball", placeIds = { 30 }, universeIds = { 40 } },
}
local owner = { userId = 123, username = "renannnhh" }
local other = { userId = 456, username = "another" }
assert(registry.resolve(profiles, 10, 0, owner, access).id == "mcpvp")
assert(registry.resolve(profiles, 10, 0, other, access).id == "universal")
assert(registry.resolve(profiles, 0, 20, other, access).id == "universal")
assert(registry.resolve(profiles, 30, 0, other, access).id == "phantom-ball")
assert(registry.resolve(profiles, 99, 0, other, access).id == "universal")
access.games.mcpvp = { mode = "allowlist", userIds = { 456 } }
assert(registry.resolve(profiles, 10, 0, other, access).id == "mcpvp")
access.games.mcpvp.blockedUserIds = { 456 }
assert(registry.resolve(profiles, 10, 0, other, access).id == "universal")
access.exodus = { mode = "disabled" }
assert(registry.resolve(profiles, 10, 0, owner, access) == nil)
access.exodus = { mode = "allowlist", userIds = { 123 } }
assert(registry.resolve(profiles, 99, 0, other, access) == nil)
access.games.universal = { mode = "disabled" }
assert(registry.resolve(profiles, 99, 0, owner, access) == nil)
local profile = { id = "universal", permissions = false }
local common = { { name = "permissions", path = "core/permissions.luau" }, { name = "state", path = "core/session.luau" } }
assert(#registry.manifest(common, profile) == 1)
assert(#common == 2)
local modules = {
  b = { __contract = { provides = {}, requires = { A = "a" } } },
  a = { __contract = { provides = {}, requires = {} } },
}
local order = linker.order({ { name = "b" }, { name = "a" } }, modules)
assert(order[1] == "a" and order[2] == "b")
modules.a.__contract.requires.B = "b"
assert(not pcall(linker.order, { { name = "b" }, { name = "a" } }, modules))
'''
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / 'access_api.luau'
            script.write_text(source)
            result = subprocess.run([binary, str(script)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
