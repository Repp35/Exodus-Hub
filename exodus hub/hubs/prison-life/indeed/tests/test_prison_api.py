"""Essential Prison Life clock, configuration and presentation contracts."""
from pathlib import Path
import os
import shutil
import sys
import unittest

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "indeed/checks"))
from runtime_api import smoke


class PrisonAPI(unittest.TestCase):
    def test_clock_api_and_owned_configuration(self):
        binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
        if not binary:
            self.skipTest("Luau unavailable")
        smoke(binary, hub_id="prison-life", assertions="""
local clock = loaded.localclock
for _, name in ipairs({ "parseTime", "formatTime", "restart", "setPreset", "teardown" }) do
  assert(type(clock[name]) == "function", name)
end
for _, text in ipairs({ "24h", "24:00", "24", "00:00", " 24H " }) do
  assert(clock.parseTime(text) == 0, text)
end
assert(clock.parseTime("8:30") == 8.5)
assert(clock.parseTime("8h") == 8)
for _, text in ipairs({ "25", "24:01", "12:60", "-1", "abc", "12:00:00" }) do
  assert(clock.parseTime(text) == nil, text)
end
assert(clock.formatTime(24) == "00:00" and clock.formatTime(8.5) == "08:30")
assert(loaded.config.validatePatch({ PrisonTimeHour = 0, PrisonTimeSpeed = 0.1, PrisonTimeFixed = false }))
assert(loaded.config.validatePatch({ PrisonTimeHour = 24, PrisonTimeSpeed = 20 }))
assert(not loaded.config.validatePatch({ PrisonTimeHour = 25 }))
assert(not loaded.config.validatePatch({ PrisonTimeSpeed = 0 }))
local definition = loaded.hubapi.getUIConfig()
assert(#definition.pages == 1 and definition.pages[1].columns == 1)
assert(definition.pages[1].id == "prison-time")
local components = definition.pages[1].sections[1].components
assert(components[1].key == "PrisonTimeEnabled")
for index = 2, #components do assert(components[index].parentKey == "PrisonTimeEnabled") end
local boundary = loaded.gamescope.create(loaded, loaded.gamecontext.getProfile())
assert(not pcall(boundary.modules.utils.setConfig, { UniversalFullbright = true }))
""")

    def test_clock_has_no_server_calls_or_gui_writes(self):
        source = (ROOT / "hubs/prison-life/local_clock.luau").read_text()
        for forbidden in ("FireServer", "InvokeServer", "ReplicatedStorage", "PlayerGui", ".Text ="):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
