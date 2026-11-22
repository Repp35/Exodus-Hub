"""Public geometry API: factors, partial radii and per-consumer windows."""
import unittest
from test_logic_reliability import COMMON, module, run_case

class GeometryAPI(unittest.TestCase):
    def check(self, case):
        run_case(COMMON + module('combat/deflectgeometry.luau') + '''
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
local attributes={DeflectRange=10.5}
local player={UserId=42,GetAttribute=function(_,key) return attributes[key] end}
local players={LocalPlayer=player,GetPlayerByUserId=function(_,id) if id==42 then return player end end}
local world={GetServerTimeNow=function() return tm end}
local data={getBallSpeedLimits=function() return 16,600 end,getDefenseSource=function() end,
 usesSharedLayout=function() return false end,getAveragePing=function() return .05 end,
 getClashContext=function() end,getSyncData=function() return {Speed=600} end}
assert(mod.setup({GameInfo=data,Utils={getPlayers=function() return players end,getWorkspace=function() return world end}}))
local function near(a,b) assert(math.abs(a-b)<1e-9,tostring(a)..' ~= '..tostring(b)) end
''' + case)

    def test_factor_preserves_fixed_range_and_scales_dynamic_components(self):
        self.check('''
for _,factor in ipairs({0,.3,1,1.5}) do
 local options={window=.4,factor=factor,latency=.05}
 local value=mod.resolve(100,options)
 near(value.noWindowParryRadius,10.5); near(value.pureRadius,8.5)
 near(value.windowRadius,40*factor); near(value.pingRadius,5*factor)
 near(value.fullRadius,10.5+45*factor)
 near(mod.getWindow(100,options),.4*factor)
 options.raw=true;near(mod.getWindow(100,options),.4)
 options.component='base';near(mod.getRadius(100,options),8.5)
 options.component='raw';near(mod.getRadius(100,options),10.5)
 options.component='resilience';near(mod.getRadius(100,options),2)
 options.component='window';near(mod.getRadius(100,options),40*factor)
 options.component='ping';near(mod.getRadius(100,options),5*factor)
end
''')

    def test_consumer_window_override_does_not_change_shared_rules(self):
        self.check('''
local baseline=mod.getDeflectWindow(600)
local value=mod.resolve(100,{window=.4,windowScale=.5,windowOffset=.02,factor=.3,ping=false})
near(value.deflectWindow,.22);near(value.fullRadius,17.1)
near(mod.getDeflectWindow(600),baseline)
local combined=mod.compose({range=8.5,extraRange=2,speed=100,window=.4,factor=.3,latency=.05})
near(combined.windowRadius,12);near(combined.pingRadius,5);near(combined.fullRadius,27.5)
near(mod.resolve(100,{window=.4,factor=.3,latency=.05,latencyFactor=1}).fullRadius,27.5)
attributes.DeflectRange=11;near(mod.getRadius(100,{factor=0}),11)
''')

    def test_training_and_ap_profiles_keep_their_existing_lead_rules(self):
        self.check('''
local training=mod.resolve(600,{profile='training',factor=.3})
near(training.deflectWindow,.2);near(training.fullRadius,46.5)
near(mod.getRadius(600,{profile='training',factor=0,component='window'}),0)
local ap=mod.resolve(600,{profile='autoParry',factor=.3,frameLead=1/60,latency=.05})
near(ap.deflectWindow,.2);near(ap.effectiveWindow,.05+.2*.3+1/60)
near(ap.fullRadius,10.5+600*ap.effectiveWindow)
''')

    def test_opponent_geometry_uses_opponent_range_and_clash_window(self):
        self.check('''
local opponent={UserId=99,GetAttribute=function(_,key) if key=='DeflectRange' then return 12 end end}
players.GetPlayerByUserId=function(_,id) if id==99 then return opponent elseif id==42 then return player end end
local ball={IsInClash=function(_,p) return p==opponent end,
 GetClashMinWindow=function() return .4 end,ApplyClashPressure=function(window,p) return window end}
-- The pressure callback follows the native method signature.
ball.ApplyClashPressure=function(_,window,p) assert(p==opponent);return window end
data.getDefenseSource=function() return ball end
local own=mod.getAutoParryGeometry(600,.4,0,0)
local other=mod.getAutoParryGeometry(600,.4,0,0,99)
near(own.noWindowParryRadius,10.5);near(other.noWindowParryRadius,12)
near(own.deflectWindow,.2);near(other.deflectWindow,.4)
assert(other.fullRadius>own.fullRadius)
''')

    def test_consumer_window_and_factor_do_not_change_native_base(self):
        self.check('''
local t=mod.getParryTiming({position=Vector3.new(40,0,0),velocity=Vector3.new(-600,0,0),syncSpeed=600,targeted=true},Vector3.zero,{window=.3,factor=.3,ping=0,frameLead=1/60})
near(t.deflectWindow,.3);near(t.effectiveWindow,.3*.3+1/60)
near(mod.getDeflectWindow(600,false),.2)
local other=mod.getParryTiming({position=Vector3.new(40,0,0),velocity=Vector3.new(-600,0,0),syncSpeed=600,targeted=true},Vector3.zero,{factor=1.2,ping=0})
near(other.deflectWindow,.2);near(other.windowFactor,1.2);near(other.effectiveWindow,.24)
''')

if __name__ == '__main__':
    unittest.main()
