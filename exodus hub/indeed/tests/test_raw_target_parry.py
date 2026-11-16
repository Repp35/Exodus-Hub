"""Offline tests for raw targeting and AP cooldown integration; no Roblox server emulation."""
import ctypes
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2] / "modules" / "logic"
LIB = ctypes.CDLL("liblua5.4.so.0")
LIB.luaL_newstate.restype = ctypes.c_void_p
LIB.luaL_openlibs.argtypes = [ctypes.c_void_p]
LIB.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
LIB.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_long, ctypes.c_void_p]
LIB.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
LIB.lua_tolstring.restype = ctypes.c_char_p
LIB.lua_close.argtypes = [ctypes.c_void_p]

def run_lua(script):
    state = LIB.luaL_newstate()
    try:
        LIB.luaL_openlibs(state)
        status = LIB.luaL_loadstring(state, script.encode())
        if not status:
            status = LIB.lua_pcallk(state, 0, 0, 0, 0, None)
        if status:
            raise AssertionError(LIB.lua_tolstring(state, -1, None).decode())
    finally:
        LIB.lua_close(state)

PRELUDE = """
local tm=10; os.clock=function() return tm end
math.clamp=function(x,a,b) return math.max(a,math.min(b,x)) end
table.clear=function(t) for k in pairs(t) do t[k]=nil end end
local V={}; V.__index=function(t,k) if k=='Magnitude' then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z) elseif k=='Unit' then local m=t.Magnitude; return setmetatable({X=t.X/m,Y=t.Y/m,Z=t.Z/m},V) end return V[k] end
V.__sub=function(a,b) return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z},V) end
V.__mul=function(a,b) return setmetatable({X=a.X*b,Y=a.Y*b,Z=a.Z*b},V) end
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
local function v(x,y) return setmetatable({X=x,Y=y or 0,Z=0},V) end
Vector3={zero=v(0)}
function typeof(x) if getmetatable(x)==V then return 'Vector3' elseif type(x)=='table' and x.instance then return 'Instance' else return type(x) end end
local frameCb
local function signal() return {Connect=function(self,fn) if not frameCb then frameCb=fn end; return {Disconnect=function() end} end} end
local player={UserId=42}; local root={Parent=true,Position=v(0),AssemblyLinearVelocity=v(0),IsA=function() return true end}
local character={Parent=true,AncestryChanged=signal(),FindFirstChild=function() return root end}
local ball={Parent=true,instance=true,IsA=function() return true end}
local snap={ball=ball,position=v(10),realPosition=v(10),velocity=v(-600),speed=600,syncSpeed=600,targetId=42,syncSequence=1}
local fires=0; local cd={source='local',blocking=false}
local u={getLocalPlayer=function() return player end,getRunService=function() return {PostSimulation=signal()} end,isActive=function() return true end,getConfigValue=function(k) if k=='AutoParryWindowFactor' then return 0.3 else return true end end,isSpamActive=function() return false end,trackCharacter=function() end,untrackCharacter=function() end,recordTransition=function() end,recordError=function() end}
local g={getDeflectAbility=function() return {} end,getSnapshotAt=function() return snap end,isSnapshotValid=function() return true end,getRootPosition=function() return root.Position end,isTrainingArea=function() return false end,observeTraining=function() return {Disconnect=function() end} end,getSyncSequence=function() return snap.syncSequence end,getAveragePing=function() return 0,0,1 end,getAutoParryGeometry=function(speed,factor) return {noWindowParryRadius=8.5,triggerPadding=1,leadTime=0.08,effectiveWindow=0.08,deflectWindow=0.2,windowFactor=factor,fullRadius=57} end}
local c={getDeflectCooldownState=function() return cd end,recordDeflectAttempt=function(at) cd.pressAt=at end}
local r={fireParry=function(_,guard) assert(guard()); fires=fires+1; return true end}

g.getBallVelocity=function() return snap.velocity end
local trainingUntil=0
c.recordTrainingDeflectAttempt=function(at) trainingUntil=at+1.45 end
c.getTrainingCooldownState=function() return {blocking=tm<trainingUntil} end
"""

class RawTargetParry(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (ROOT / "autoparry.luau").read_text()
        cls.source = re.sub(r"([A-Za-z_][\w.]*) \+= ([^;\n]+?)(?=;|\n| end)", lambda m: f"{m[1]} = {m[1]} + ({m[2]})", source)

    def check_ap(self, case):
        run_lua(PRELUDE + "local ap=(function()\n" + self.source + "\nend)()\n" + """
assert(ap.setup({Utils=u,GameInfo=g,Remote=r,Cooldown=c}))
assert(ap.bindCharacter(character))
local function packet(target)
  snap.syncSequence=snap.syncSequence+1; snap.targetId=target
  ap.onBallSync({Sequence=snap.syncSequence,TargetPlayerID=target})
end
""" + case)

    def test_disabled_ap_blocks_public_fire_and_pending_guard(self):
        self.check_ap("""
local enabled=true; local config=u.getConfigValue
u.getConfigValue=function(k) if k=='AutoParry' then return enabled end return config(k) end
local pending
r.fireParry=function(_,guard) pending=guard; assert(guard()); fires=fires+1; return true end
packet(42); assert(pending and pending())
enabled=false
assert(not pending(),'pending request survived disabling AP')
packet(99); packet(42)
assert(not ap.fire(),'public fire bypassed disabled AP')
frameCb(1/60); assert(fires==1)
""")

    def test_pending_request_revalidates_ball_and_distance(self):
        for change in (
            "snap.position=v(300)", "snap.realPosition=v(300)",
            "snap.targetId=99", "snap.teleported=true", "snap.locked=true",
            "snap.ballValid=false", "snap.valid=false", "snap.resetting=true", "snap.targetUncertain=true", "cd.blocking=true",
            "snap.syncSpeed=0/0", "snap.syncSpeed=0", "snap.syncAt=tm-1",
            "snap.syncAt=0/0", "snap.realPosition=v(0/0)",
            "snap.ball={Parent=true}", "ball.Parent=nil", "root.Parent=nil",
            "character.Parent=nil", "snap.mode='training'",
        ):
            with self.subTest(change=change):
                self.check_ap("""
local pending
r.fireParry=function(_,guard) pending=guard; assert(guard()); fires=fires+1; return true end
packet(42); assert(pending and pending())
""" + change + "\nassert(not pending(),'stale pending request was allowed')")

    def test_reset_position_cannot_click_through_normal_or_redirect_path(self):
        self.check_ap("""
r.fireParry=function(_,guard) if not guard() then return false end fires=fires+1; return true end
snap.position=v(10); snap.realPosition=v(300)
packet(42); assert(fires==0,'clicked using reset visual position')
assert(not ap.fire(),'public fire used stale cached distance')
tm=tm+1; assert(not ap.tryRedirectReturn(snap,tm)); assert(fires==0)
snap.position=v(300); frameCb(1/60); assert(fires==0)
snap.position=v(10); snap.realPosition=v(10); tm=tm+1
frameCb(1/60); assert(fires==1,'did not recover after valid nearby data')
""")

    def test_optional_sync_fields_can_be_absent(self):
        self.check_ap("""
snap.realPosition=nil; snap.syncDirection=nil; snap.syncAt=nil; snap.syncSpeed=nil
packet(42); assert(fires==1,'optional sync fields blocked valid AP')
""")

    def test_bounded_sync_lag_does_not_block_near_ball(self):
        self.check_ap("""
snap.position=v(10); snap.realPosition=v(70); snap.syncAt=tm-.1
packet(42); assert(fires==1,'normal sync delay blocked AP')
""")

    def test_raw_target_has_no_confirmation_or_visual_fallback(self):
        source = (ROOT / "aux/gameinfo.luau").read_text()
        target = source[source.index("local function targetId("):source.index("local function findBall()")]
        run_lua(target + """
assert(targetId({TargetPlayerID=42,HighlightTargetPlayerID=99})==42)
assert(targetId({TargetPlayerID=99,HighlightTargetPlayerID=42})==99)
assert(targetId({TargetPlayerID=42})==42)
assert(targetId({TargetPlayerID=0})==0)
assert(targetId({HighlightTargetPlayerID=42,Targeted=true})==-1)
assert(targetId(nil)==-1)
assert(targetId({TargetPlayerID=99})==99)
""")

    def test_ready_cooldown_does_not_delay_first_click_or_fast_returns(self):
        self.check_ap("""
packet(42); assert(fires==1,'first target packet did not click immediately')
for i=1,16 do
  tm=tm+1/32; packet(99); tm=tm+1/32; packet(42)
end
assert(fires==17,'ready cooldown throttled fresh target cycles')
""")

    def test_same_target_stays_blocked_after_success(self):
        self.check_ap("""
packet(42); cd.lastParriedAt=tm+0.001
for i=1,16 do tm=tm+1/16; packet(42); frameCb(1/60) end
assert(fires==1,'repeated packet or successful cooldown reset duplicated click')
packet(99); packet(42); assert(fires==2)
""")

    def test_actual_cooldown_still_blocks_first_click(self):
        self.check_ap("""
cd.blocking=true; packet(42); assert(fires==0,'ignored real cooldown')
cd.blocking=false; frameCb(1/60); assert(fires==1,'wait added after ready cooldown')
""")

    def test_cooldown_still_blocks_fresh_target_return(self):
        self.check_ap("""
packet(42); packet(99); cd.blocking=true; packet(42)
assert(fires==1,'fresh target bypassed actual cooldown')
cd.blocking=false; frameCb(1/60); assert(fires==2)
""")

    def test_miss_retry_requires_cooldown_to_finish(self):
        self.check_ap("""
packet(42); cd.miss=true; cd.blocking=true
frameCb(1/60); assert(fires==1,'retried during miss cooldown')
cd.blocking=false; frameCb(1/60); assert(fires==2,'lost cooldown-based miss recovery')
""")

    def test_training_cooldown_and_miss_recovery_remain(self):
        self.check_ap("""
snap.mode='training'; snap.trainingRound=1
frameCb(1/60); assert(fires==1)
tm=tm+1; frameCb(1/60); assert(fires==1,'ignored training cooldown')
tm=tm+0.46; frameCb(1/60); assert(fires==2,'lost training cooldown recovery')
""")

    def test_no_target_and_redirect_cannot_click_for_an_opponent(self):
        self.check_ap("""
packet(99); assert(fires==0)
assert(ap.tryRedirectReturn(snap,tm)==false); assert(fires==0)
packet(42); assert(fires==1)
packet(-1); packet(42); assert(fires==2,'raw no-target departure did not rearm')
""")

    def test_outside_window_still_waits_for_arrival(self):
        self.check_ap("""
snap.position=v(300); packet(42); assert(fires==0)
snap.position=v(10); frameCb(1/60); assert(fires==1)
""")

    def test_base_radius_fires_without_incoming_velocity(self):
        for velocity in ('v(0)', 'v(600)', 'v(0,600)'):
            with self.subTest(velocity=velocity):
                self.check_ap("snap.position=v(8.5); snap.velocity=" + velocity + """
packet(42); assert(fires==1,'base radius incorrectly depends on incoming velocity')
frameCb(1/60); packet(42); assert(fires==1,'radius check duplicated same cycle')
""")

    def test_inside_radius_keeps_target_and_cooldown_requirements(self):
        self.check_ap("""
snap.position=v(8); snap.velocity=v(0)
packet(99); assert(fires==0,'radius bypassed target')
cd.blocking=true; packet(42); assert(fires==0,'radius bypassed cooldown')
cd.blocking=false; frameCb(1/60); assert(fires==1,'ready radius click delayed')
""")

    def test_training_base_radius_does_not_require_closing_velocity(self):
        self.check_ap("""
snap.mode='training'; snap.trainingRound=1; snap.position=v(8.5); snap.velocity=v(600)
frameCb(1/60); assert(fires==1,'training base radius still requires incoming velocity')
""")

    def test_redirect_radius_keeps_cooldown(self):
        self.check_ap("""
cd.blocking=true; snap.position=v(8.5); snap.velocity=v(600)
packet(42); assert(fires==0)
assert(ap.tryRedirectReturn(snap,tm)==false); assert(fires==0,'redirect radius bypassed cooldown')
cd.blocking=false; assert(ap.tryRedirectReturn(snap,tm)); assert(fires==1)
""")

    def test_single_window_exact_boundaries_and_speed_limits(self):
        geometry_source = (ROOT / "aux/gameinfo.luau").read_text()
        geometry_source = geometry_source[geometry_source.index("function GameInfo.getAutoParryGeometry("):geometry_source.index("function GameInfo.getProjectedDeflectRadius(")]
        for speed, window in ((16, 0.5), (308, 0.375), (600, 0.25)):
            with self.subTest(speed=speed):
                self.check_ap("""
local GameInfo=g
local CONFIG={RANGE_BASE=8.5,AUTO_PARRY_TRIGGER_PADDING=1}
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
g.getBallSpeedLimits=function() return 16,600 end
g.getDeflectRange=function() return 11.5 end
g.getAveragePing=function() return 0.05,0.05,1 end
""" + geometry_source + f"""
snap.syncSpeed={speed}; snap.speed={speed}; snap.velocity=v({speed})
local boundary=11.5+1+{speed}*({window}*0.4+0.05+1/60)
snap.position=v(boundary+0.001); packet(42)
assert(fires==0,'clicked outside the 0.4 window')
local timing=ap.getTiming(snap)
assert(math.abs(timing.deflectWindow-{window})<1e-9)
assert(timing.windowFactor==0.4,'stored old factor changed match gate')
assert(math.abs(timing.triggerDistance-boundary)<1e-9)
snap.position=v(boundary); frameCb(1/60)
assert(fires==1,'exact distance boundary did not click')
frameCb(1/60); assert(fires==1,'duplicate click after firing')
""")

    def test_window_ignores_trajectory_and_player_velocity(self):
        for velocity in ('v(0)', 'v(600)', 'v(0,600)', 'v(-600)'):
            with self.subTest(velocity=velocity):
                self.check_ap("snap.velocity=" + velocity + """
snap.position=v(57.001); root.AssemblyLinearVelocity=v(100)
packet(42); assert(fires==0,'trajectory bypassed distance window')
snap.position=v(57); root.AssemblyLinearVelocity=v(-100)
frameCb(1/60); assert(fires==1,'velocity added an extra gate')
""")

    def test_redirect_uses_the_same_window(self):
        self.check_ap("""
snap.position=v(57.001); packet(42)
assert(fires==0); assert(not ap.tryRedirectReturn(snap,tm))
snap.position=v(57); snap.velocity=v(600)
assert(ap.tryRedirectReturn(snap,tm)); assert(fires==1)
frameCb(1/60); assert(fires==1)
""")

    def test_miss_retry_uses_the_same_window_after_cooldown(self):
        self.check_ap("""
packet(42); cd.miss=true; cd.blocking=true
snap.position=v(57); frameCb(1/60); assert(fires==1)
cd.blocking=false; frameCb(1/60); assert(fires==2)
""")

    def test_defense_radius_is_independent_of_window(self):
        self.check_ap("""
g.getAveragePing=function() return 0.05,0.05,1 end
packet(99); snap.position=v(100)
local first=ap.getTiming(snap)
local geometry=g.getAutoParryGeometry
g.getAutoParryGeometry=function(...)
  local result=geometry(...); result.deflectWindow=0.85; return result
end
local second=ap.getTiming(snap)
assert(first.defenseRadius==second.defenseRadius)
assert(first.tti==second.tti,'window changed actual TTI to radius')
assert(first.radiusGateLead~=second.radiusGateLead)
""")

if __name__ == "__main__":
    unittest.main()
