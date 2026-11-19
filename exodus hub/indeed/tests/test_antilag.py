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
assert(defaults.AntiLagRenderDistance==128 and defaults.AntiLagFloorCull==true)
assert(defaults.AntiLagClashCull==nil and defaults.AntiLagRemoveTextures==nil)
assert(defaults.AntiLagHideLobby==true)
assert(defaults.AntiLagRemoveEffects==true)
assert(config.validatePatch({AntiLagEnabled=true,AntiLagRenderDistance=950}))
assert(not config.validatePatch({AntiLagEnabled='yes'}))
assert(not config.validatePatch({AntiLagRenderDistance=math.huge}))
""")

    def test_distance_setting_is_used_with_bounds(self):
        from test_raw_target_parry import run_lua
        code = SOURCE[SOURCE.index('local function requestedProfile()'):SOURCE.index('local function loadNativeModules(')]
        run_lua('''
local PROFILE={CullDistance=128}
local CONFIG={defaults={AntiLagRenderDistance=128}}
local distance=128
local function setting(key) if key=='AntiLagRenderDistance' then return distance end return false end
function table.clone(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
function math.clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
'''+code+'''
assert(requestedProfile().CullDistance==128)
distance=64; assert(requestedProfile().CullDistance==64)
distance=400; assert(requestedProfile().CullDistance==400)
distance=0; assert(requestedProfile().CullDistance==1)
distance=2000; assert(requestedProfile().CullDistance==1200)
distance=math.huge; assert(requestedProfile().CullDistance==128)
''')

    def test_optional_terrain_failure_is_reported_in_status_without_warning(self):
        from test_raw_target_parry import run_lua
        report = SOURCE[SOURCE.index('  local function reportUnavailable('):SOURCE.index('  local function inScope(')]
        report = report.replace('unsupportedCount += 1', 'unsupportedCount = unsupportedCount + 1')
        status = SOURCE[SOURCE.index('  function controller:GetStatus()'):SOURCE.index('  function controller:Destroy()')]
        run_lua("""
table.clone=function(t) local copy={} for k,v in pairs(t) do copy[k]=v end return copy end
local unsupported={};local unsupportedCount=0;local warnings=0
warn=function() warnings=warnings+1 end
local controller={};local enabled,alive,destroying,workerRunning=false,true,false,false
local records={};local changedProperties,restoreFailures,runtimeFailures,generation=0,0,0,0
local function workAvailable() return false end
"""+report+status+"""
reportUnavailable('Terrain.Decoration');reportUnavailable('Terrain.Decoration')
assert(warnings==0 and unsupportedCount==1)
local s=controller:GetStatus();assert(s.UnsupportedProperties['Terrain.Decoration'] and s.Unsupported==1)
s.UnsupportedProperties['Terrain.Decoration']=nil
assert(controller:GetStatus().UnsupportedProperties['Terrain.Decoration'],'status exposed mutable internal state')
reportUnavailable('Lighting.Unknown');assert(warnings==1 and unsupportedCount==2,'other unsupported failures were hidden')
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
local children={'AntiLagRenderDistance','AntiLagRemoveSwordSounds','AntiLagRemoveEffects'}
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
