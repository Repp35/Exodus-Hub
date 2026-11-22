import unittest
from pathlib import Path
from test_logic_reliability import COMMON, module, run_case
from test_defenseengine import STACK

CD_ENV = '''
local heartbeat=signal();local ability={Cooldown=0}
local u={getRunService=function() return {Heartbeat=heartbeat} end,getReplicatedStorage=function() return nil end,
 trackGlobal=function() end,untrackGlobal=function() end,recordError=function() end}
local g={getDeflectAbility=function() return ability end}
'''
class MissRecoveryTests(unittest.TestCase):
 def test_miss_persists_when_entire_cooldown_elapses_between_reads(self):
  run_case(COMMON+CD_ENV+module('combat/cooldown.luau')+'''
   assert(mod.setup({Utils=u,GameInfo=g}))
   ability.Cooldown=.4;ability.PendingPredictUntil=tm+.2;ability.PendingPressAt=tm
   mod.recordDeflectAttempt(tm)
   tm=tm+.5;ability.Cooldown=0;ability.PendingPredictUntil=nil
   local cd=mod.getDeflectCooldownState()
   assert(cd.miss and cd.phase=='miss_finished' and cd.blocking==false)
   assert(cd.pressAt==10 and cd.windowExpired)
  ''')
 def test_prediction_window_does_not_count_as_miss(self):
  run_case(COMMON+CD_ENV+module('combat/cooldown.luau')+'''
   assert(mod.setup({Utils=u,GameInfo=g}))
   ability.Cooldown=1.45;ability.PendingPredictUntil=tm+.2;ability.PendingPressAt=tm
   mod.recordDeflectAttempt(tm);assert(not mod.getDeflectCooldownState().miss)
   ability.Cooldown=0;ability.PendingPredictUntil=nil;ability.PredictedResetUntil=tm+.5
   tm=tm+.3;assert(not mod.getDeflectCooldownState().miss)
  ''')
 def test_confirmed_parry_cancels_completed_miss(self):
  run_case(COMMON+CD_ENV+module('combat/cooldown.luau')+'''
   local parried=signal();mod.getDeflectServerEvents=function() return {parried=parried} end
   assert(mod.setup({Utils=u,GameInfo=g}))
   ability.Cooldown=.4;ability.PendingPressAt=tm;mod.recordDeflectAttempt(tm)
   tm=tm+.1;parried:Fire();ability.Cooldown=0;tm=tm+.5
   assert(not mod.getDeflectCooldownState().miss)
  ''')
 def test_real_cooldown_rearms_real_ap_without_target_change(self):
  run_case(STACK+r'''
   afterGuard=function() ability.Cooldown=.4;ability.PendingPredictUntil=tm+.1;ability.PendingPressAt=tm+.0002 end
   packetTo(42);assert(calls==1)
   tm=tm+.5;ability.Cooldown=0;ability.PendingPredictUntil=nil;afterGuard=nil
   packetTo(42);assert(calls==2,'real miss recovery failed to rearm same target')
   ap.teardown();cd.teardown()
  ''')
 def test_actual_ap_timing_delegates_missing_danger_to_geometry(self):
  run_case(STACK+r'''
   local t=ap.getTiming({position=v(10),velocity=v(-600),syncSpeed=600,speed=600,targeted=true},tm,v(),.85)
   assert(t and math.abs(t.timeToKill-.01)<1e-6,'missing danger time blocked Fierce')
  ''')

if __name__=='__main__':unittest.main()
