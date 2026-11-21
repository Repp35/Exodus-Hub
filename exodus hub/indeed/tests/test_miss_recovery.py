import unittest
from pathlib import Path
from test_logic_reliability import COMMON, module, run_case
from test_defenseengine import FIXTURE, parry_runtime

CD_ENV = '''
local heartbeat=signal();local ability={Cooldown=0}
local u={getRunService=function() return {Heartbeat=heartbeat} end,getReplicatedStorage=function() return nil end,
 trackGlobal=function() end,untrackGlobal=function() end,recordError=function() end}
local g={getDeflectAbility=function() return ability end}
'''
class MissRecoveryTests(unittest.TestCase):
 def test_miss_persists_when_entire_cooldown_elapses_between_reads(self):
  run_case(COMMON+CD_ENV+module('aux/cooldown.luau')+'''
   assert(mod.setup({Utils=u,GameInfo=g}))
   ability.Cooldown=.4;ability.PendingPredictUntil=tm+.2;ability.PendingPressAt=tm
   mod.recordDeflectAttempt(tm)
   tm=tm+.5;ability.Cooldown=0;ability.PendingPredictUntil=nil
   local cd=mod.getDeflectCooldownState()
   assert(cd.miss and cd.phase=='miss_finished' and cd.blocking==false)
   assert(cd.pressAt==10 and cd.windowExpired)
  ''')
 def test_prediction_window_does_not_count_as_miss(self):
  run_case(COMMON+CD_ENV+module('aux/cooldown.luau')+'''
   assert(mod.setup({Utils=u,GameInfo=g}))
   ability.Cooldown=1.45;ability.PendingPredictUntil=tm+.2;ability.PendingPressAt=tm
   mod.recordDeflectAttempt(tm);assert(not mod.getDeflectCooldownState().miss)
   ability.Cooldown=0;ability.PendingPredictUntil=nil;ability.PredictedResetUntil=tm+.5
   tm=tm+.3;assert(not mod.getDeflectCooldownState().miss)
  ''')
 def test_confirmed_parry_cancels_completed_miss(self):
  run_case(COMMON+CD_ENV+module('aux/cooldown.luau')+'''
   local parried=signal();mod.getDeflectServerEvents=function() return {parried=parried} end
   assert(mod.setup({Utils=u,GameInfo=g}))
   ability.Cooldown=.4;ability.PendingPressAt=tm;mod.recordDeflectAttempt(tm)
   tm=tm+.1;parried:Fire();ability.Cooldown=0;tm=tm+.5
   assert(not mod.getDeflectCooldownState().miss)
  ''')
 def test_real_cooldown_rearms_real_ap_without_target_change(self):
  run_case(FIXTURE+module('aux/cooldown.luau')+'local cooldown=mod\n'+parry_runtime()+r'''
   setup();local u={getRunService=function() return S.runs end,getReplicatedStorage=function() return nil end,
    trackGlobal=function() end,untrackGlobal=function() end,recordError=function() end}
   S.ability.Cooldown=0
   assert(cooldown.setup({Utils=u,GameInfo={getDeflectAbility=function() return S.ability end}}))
   local original=S.ability.Deflect
   function S.ability:Deflect()
    original(self);self.Cooldown=.4;self.PendingPredictUntil=clock+.1;self.PendingPressAt=clock+.0002
   end
   local c=assert(mod.create({canAct=function() return true end,getCooldown=cooldown.getDeflectCooldownState,
    onAttempt=function(_,at) cooldown.recordDeflectAttempt(at) end}))
   matchPacket(123);assert(S.ability.calls==1)
   clock=clock+.5;S.ability.Cooldown=0;S.ability.PendingPredictUntil=nil
   matchPacket(123);assert(S.ability.calls==2,'real miss recovery failed to rearm same target')
   c.stop();cooldown.teardown()
  ''')
 def test_actual_ap_timing_delegates_missing_danger_to_geometry(self):
  source=(Path(__file__).resolve().parents[2]/'modules/logic/autoparry.luau').read_text()
  timing=source[source.index('function AutoParry.getTiming('):source.index('function AutoParry.getRadius(')]
  run_case(COMMON+module('aux/deflectgeometry.luau')+r'''

   function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
   local CONFIG={MIN_PARRY_SPEED=16}
   local AutoParry={};local deflectGeometry=mod
   local state={ping=0};local gameInfo={}
   local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
   local function vector(x) return typeof(x)=='Vector3' end
   local function validBallSpeed(x) return finite(x) and x>=0 and x<=1000 end
   local function clock() return tm end
   local function runtimeTiming() return nil end
   local function samplePing() end
   local function matchTiming() return nil end
   local function radius() return {noWindowParryRadius=8.5,fullRadius=20,effectiveWindow=.2,leadTime=.2} end
   local function adaptiveLead() return .2,.9 end
   local function trajectory(p,v,r,s,g) return deflectGeometry.getTrajectory(p,v,r,s,g) end
   local function radiusTiming() return .1,4,.2 end
   deflectGeometry.getDefensePhysics=function() return {killRadius=4} end
  '''+timing+r'''

   local timing=AutoParry.getTiming({position=v(10),velocity=v(-600),syncSpeed=600,speed=600,targeted=true},tm,v(0),.9)
   assert(timing and math.abs(timing.timeToKill-.01)<1e-6,'missing danger time blocked Fierce')
  ''')

if __name__=='__main__':unittest.main()
