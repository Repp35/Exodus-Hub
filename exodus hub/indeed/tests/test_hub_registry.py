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
            (hub / 'modules').mkdir()
            (hub / 'modules/movement.luau').write_text('return { __contract = {} }')
            profiles = BUILDER.discover(root)
            self.assertEqual(profiles[0]['id'], 'new-pvp')
            self.assertEqual(profiles[0]['modules'], [{'name': 'movement', 'path': 'hubs/new-pvp/modules/movement.luau'}])
            (hub / 'modules/permissions.luau').write_text('return { __contract = {} }')
            with self.assertRaises(ValueError): BUILDER.discover(root)

    def test_shared_modules_are_not_copied_into_games(self):
        import sys
        sys.path.insert(0, str(ROOT / 'indeed/checks'))
        from manifests import common, hub_entries
        shared = dict(common())
        self.assertIn('autojump', shared)
        self.assertIn('camera', shared)
        for info in (ROOT / 'hubs').glob('*/hub.json'):
            game = dict(hub_entries(info.parent.name))
            self.assertFalse(set(shared) & set(game))
            for path in game.values():
                self.assertNotIn('/front/controllers/', path)
                self.assertNotIn('/features/', path)
        self.assertTrue((ROOT / 'modules/front/controllers/floating.luau').is_file())

    def test_registry_routes_ids_and_composes_only_the_selected_game(self):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary: self.skipTest('Luau required')
        code = 'local Registry = (function()\n' + (ROOT / 'hubs/registry.luau').read_text() + '\nend)()\n'
        code += 'local profiles = { { id = "sample", title = "Sample", placeIds = { 12 }, universeIds = { 13 }, notification = "Sample loaded", modules = { { name = "samplelogic", path = "hubs/sample/modules/core/samplelogic.luau" } } } }\n'
        code += '''
local supported = Registry.select(profiles, 12, 0)
assert(supported.id == "sample" and supported.notification)
assert(Registry.select(profiles, 888, 13).id == "sample")
local universal = Registry.select(profiles, 888, 999)
assert(universal.id == "universal" and universal.modules == nil)
local base = { { name = "ui", path = "modules/front/ui.luau" }, { name = "runtime", path = "modules/core/runtime.luau" } }
assert(#Registry.merge(base, universal.modules) == #base)
local merged = Registry.merge(base, supported.modules)
assert(#merged == 3 and merged[3].name == "samplelogic" and #base == 2)
assert(not pcall(Registry.merge, base, { { name = "ui", path = "hubs/sample/modules/front/ui.luau" } }))
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
