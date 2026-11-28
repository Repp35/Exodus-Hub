"""Essential MM2 module exports, configuration, dependencies and UI contracts."""
from pathlib import Path
import os
import shutil
import sys
import unittest

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "indeed/checks"))
from runtime_api import smoke

class MM2API(unittest.TestCase):
    def test_shared_runtime_and_game_api(self):
        binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
        if not binary:
            self.skipTest("Luau unavailable")
        smoke(binary, hub_id="mm2", assertions="""
local definition = loaded.hubapi.getUIConfig()
assert(definition.pageOrder[1] == "mm2-farm")
assert(type(loaded.hubapi.getControls().onMM2Shoot) == "function")
assert(type(loaded.hubapi.getControls().onMM2Throw) == "function")
for _, name in ipairs({ "mm2coin", "mm2map", "mm2match", "mm2drops", "mm2farm", "mm2pickup", "mm2maptools", "mm2combat", "mm2shoot", "mm2alerts", "mm2esp" }) do
  assert(type(loaded[name].create) == "function", name)
end
local configured = loaded.uiconfig.getPages(definition)
for _, page in ipairs(configured) do
  if page.id == "config" then assert(page.title == "Configurações" and page.utility == true) end
end
local defaults = loaded.config.defaults()
assert(defaults.ShootMiniSquare == true and defaults.KnifeMiniSquare == true)
assert(defaults.ShootKeybind == Enum.KeyCode.Q and defaults.KnifeThrowKeybind == Enum.KeyCode.E)
assert(loaded.config.validatePatch({ ShootKeybind = Enum.KeyCode.R, KnifeThrowKeybind = Enum.KeyCode.T, MM2AutoFarmKeybind = Enum.KeyCode.F }))
for _, mini in ipairs(definition.miniBalls) do assert(mini.mobileOnly == true) end
for _, page in ipairs(definition.pages) do
  for _, section in ipairs(page.sections) do
    for _, component in ipairs(section.components) do
      if component.action == "mm2Shoot" or component.action == "mm2Throw" then
        assert(component.kind == "keybind" and component.desktopOnly == true)
        assert(component.shortcutKey == component.key)
      end
      if not component.mobileOnly and (component.kind == "toggle" or component.kind == "checkbox" or component.kind == "button") then
        assert(component.shortcutKey and loaded.config.validatePatch({ [component.shortcutKey] = Enum.KeyCode.Unknown }))
      end
    end
  end
end
assert(loaded.config.validatePatch({ AutoKnifeThrow = true, KnifeCone = 35, ShootMiniScale = 1.25 }))
local boundary = loaded.gamescope.create(loaded, loaded.gamecontext.getProfile())
local page = boundary.modules.ui.addPage({ id = "api-contract", title = "API", columns = 1, sections = {} })
local section = page.addSection({ title = "Own controls" })
assert(type(section.toggle({ title = "Shoot", key = "ManualShootMurder" }).setValue) == "function")
assert(not pcall(section.toggle, { title = "Foreign", key = "UniversalFly" }))
assert(not pcall(boundary.modules.utils.setConfig, { UniversalFly = true }))
assert(not pcall(boundary.modules.utils.setConfig, { MiniUIScale = 1.5 }))

""")

if __name__ == "__main__":
    unittest.main()
