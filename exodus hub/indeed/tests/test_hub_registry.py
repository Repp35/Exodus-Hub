"""Automatic discovery and routing for supported and unknown Roblox games."""
from pathlib import Path
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('build_hub_catalog', ROOT / 'indeed/tools/build_hub_catalog.py')
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)

class HubRegistry(unittest.TestCase):
    def test_catalog_matches_folders(self):
        self.assertEqual(BUILDER.tokens((ROOT / 'hubs/catalog.luau').read_text()), BUILDER.tokens(BUILDER.render(BUILDER.discover())))

    def test_new_folder_is_discovered_without_loader_edits(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            hub = root / 'hubs/new-pvp'
            hub.mkdir(parents=True)
            (hub / 'hub.json').write_text(json.dumps({'title': 'New PVP', 'placeIds': [123]}))
            (hub / 'movement.luau').write_text('return { __contract = {} }')
            profiles = BUILDER.discover(root)
            self.assertEqual(profiles[0]['id'], 'new-pvp')
            self.assertEqual(profiles[0]['modules'], [{'name': 'movement', 'path': 'hubs/new-pvp/movement.luau'}])
            (hub / 'permissions.luau').write_text('return { __contract = {} }')
            with self.assertRaises(ValueError): BUILDER.discover(root)

    def test_registry_routes_ids_and_composes_only_the_selected_game(self):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary: self.skipTest('Luau required')
        code = 'local Registry = (function()\n' + (ROOT / 'hubs/registry.luau').read_text() + '\nend)()\n'
        code += 'local profiles = (function()\n' + (ROOT / 'hubs/catalog.luau').read_text() + '\nend)()\n'
        code += '''
local phantom = Registry.select(profiles, 12979690461, 0)
assert(phantom.id == "phantom-ball" and phantom.notification)
assert(Registry.select(profiles, 888, 4538598064).id == "phantom-ball")
local universal = Registry.select(profiles, 888, 999)
assert(universal.id == "universal" and universal.modules == nil and universal.notification ~= phantom.notification)
local base = { { name = "ui", path = "modules/front/ui.luau" }, { name = "runtime", path = "modules/core/runtime.luau" } }
local common = Registry.merge(base, universal.modules)
assert(#common == #base)
for _, entry in ipairs(common) do assert(not entry.path:match("^hubs/")) end
local merged = Registry.merge(base, phantom.modules)
local found = {}
for _, entry in ipairs(merged) do assert(not found[entry.name]); found[entry.name] = entry.path end
assert(found.ui == base[1].path and found.runtime == "hubs/phantom-ball/runtime.luau")
assert(found.autoparry and #base == 2)
local future = { id = "future", placeIds = { 12 }, universeIds = { 13 }, title = "Future", notification = "Future loaded" }
table.insert(profiles, future)
assert(Registry.select(profiles, 12, 4538598064).id == "future", "Exact place ID must take precedence")
assert(Registry.select(profiles, 999, 13).id == "future")
assert(not pcall(Registry.merge, base, { { name = "permissions", path = "hubs/future/permissions.luau" } }))
assert(not pcall(Registry.merge, base, { { name = "bad", path = "hubs/future/../bad.luau" } }))
print("Automatic hub routing and manifest composition OK")
'''
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'registry.luau'
            path.write_text(code)
            result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

if __name__ == '__main__': unittest.main()
