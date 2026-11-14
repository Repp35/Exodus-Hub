"""Anti lag configuration and nested page behavior on both device layouts."""
import unittest
from pathlib import Path

import test_api_contracts as contracts
import test_ui_library as ui

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "modules/logic/extras/antilag.luau").read_text()
CONFIG = contracts.table_after(SOURCE, "CONFIG")


class AntiLagTests(unittest.TestCase):
    def run_ui(self, script):
        return ui.UILibraryTests.run_lua(self, script)

    def test_defaults_register_in_the_real_config_schema(self):
        self.run_ui(ui.module("config") + "local definition={" + CONFIG + "}\n" + """
assert(config.register('antilag',definition))
local defaults=config.defaults()
assert(defaults.AntiLagEnabled==false and defaults.AntiLagRemoveSwordSounds==true)
assert(defaults.AntiLagRenderDistance==160)
assert(defaults.AntiLagRemoveLighting==true and defaults.AntiLagHideLobby==true)
assert(defaults.AntiLagRemoveFog==false and defaults.AntiLagRemoveEffects==true and defaults.AntiLagDisableTextures==true)
assert(config.validatePatch({AntiLagEnabled=true,AntiLagRenderDistance=950}))
assert(not config.validatePatch({AntiLagEnabled='yes'}))
assert(not config.validatePatch({AntiLagRenderDistance=math.huge}))
""")

    def test_children_only_appear_while_active_on_desktop_and_mobile(self):
        for desktop in (True, False):
            with self.subTest(desktop=desktop):
                self.run_ui("local definition={" + CONFIG + "}\n" + """
for key,value in pairs(definition.defaults) do config[key]=value end
local baseline=listenerCount()
local kit=newKit({reducedMotion=true})
local pages=uipages.create(kit,panel,uiconfig.pages,{desktop=DESKTOP,read=utils.getConfigValue})
pages.select('antilag',false)
assert(#pages.get('antilag').columns==1)
local enabled=pages.getControl('AntiLagEnabled')
local children={'AntiLagRenderDistance','AntiLagRemoveLighting','AntiLagRemoveSwordSounds','AntiLagHideLobby','AntiLagRemoveFog','AntiLagRemoveEffects','AntiLagDisableTextures'}
for _,key in ipairs(children) do assert(not uiruntime.isVisible(pages.getControl(key).Root),key) end
assert(enabled.activate());finishTweens()
for _,key in ipairs(children) do assert(uiruntime.isVisible(pages.getControl(key).Root),key) end
assert(config.AntiLagRemoveSwordSounds==true)
assert(enabled.activate());finishTweens()
for _,key in ipairs(children) do assert(not uiruntime.isVisible(pages.getControl(key).Root),key) end
pages.destroy();kit.destroy();finishTweens()
assert(listenerCount()==baseline and activeTweenCount()==0)
""".replace("DESKTOP", "true" if desktop else "false"))


if __name__ == "__main__":
    unittest.main()
