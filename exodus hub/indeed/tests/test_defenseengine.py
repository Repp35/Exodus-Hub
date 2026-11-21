"""Execute the integrated V14 engine, not a second implementation of its policy."""
from pathlib import Path
import unittest
from test_logic_reliability import module, run_case

def parry_runtime():
 source=(Path(__file__).resolve().parents[2]/'modules/logic/autoparry.luau').read_text()
 start=source.index('local function createParryRuntime(deps)')
 end=source.index('-- ap-adapter',start)
 return 'local mod=(function()\n'+source[start:end]+'\nreturn {create=createParryRuntime}\nend)()\n'

FIXTURE = (Path(__file__).parent / 'fixtures/defenseengine.lua').read_text()
BOOT = r"""
local enabled, spam = true, false
local attempts, published, peak = {}, {}, 0
local function start()
 local c,err=mod.create({
  canAct=function(mode) return enabled and (mode=='training' or not spam) end,
  onAttempt=function(mode,at) attempts[#attempts+1]={mode=mode,at=at} end,
  onState=function(v) published=v end,
  onStats=function(v) peak=math.max(peak,v.maxCps) end,
 })
 assert(c,err);return c
end
"""

class DefenseEngineTests(unittest.TestCase):
 def check_lua(self, case):
  run_case(FIXTURE + parry_runtime() + BOOT + case + r"""
  for _,msg in ipairs(logs) do
   assert(not msg:find('[AutoParry] ',1,true),msg)
  end
  """)

 def test_clash_never_repeats_without_a_new_flight(self):
  self.check_lua(r"""
   setup();S.gb.clash=true;local c=start();matchPacket(123)
   for i=1,40 do matchPacket(123,{dt=.05,speed=600});render();heartbeat() end
   check(S.ability.calls==1,'clash repeats excluded from hub AP')
   matchPacket(456);matchPacket(123);check(S.ability.calls==2,'away and return rearms')
   check(#attempts==2,'one notification per native call');c.stop()
  """)

 def test_sources_and_visual_debounce(self):
  self.check_lua(r"""
   setup();local c=start();attribute(123);check(S.ability.calls==1,'attribute immediate')
   matchPacket(456);matchPacket(123);check(S.ability.calls==1,'stale network echo cannot duplicate')
   attribute(456);attribute(123);check(S.ability.calls==2,'attribute rearm');c.stop()
   setup();c=start();matchPacket(456,{highlightId=123});check(S.ability.calls==1,'highlight ID');c.stop()
   setup();S.native.IsLocalTarget=function() return true end;c=start();matchPacket(456)
   check(S.ability.calls==1,'native provider');c.stop()
   setup();c=start();S.ball.Color=red;render();check(S.ability.calls==0,'single red frame rejected')
   for i=1,10 do S.runs.PreSimulation:Fire();S.runs.PostSimulation:Fire() end
   check(S.ability.calls==0,'physics phases do not count as visual frames')
   render();check(S.ability.calls==1,'two render frames accepted');c.stop()
  """)

 def test_confirmed_returns_without_negative_packets(self):
  self.check_lua(r"""
   setup();local c=start();matchPacket(123)
   S.hit:Fire('predicted',123);matchPacket(123,{dt=.05});check(S.ability.calls==1,'prediction is no proof')
   S.hit:Fire('parry',456);check(S.ability.calls==1,'other owner is no proof')
   S.hit:Fire('parry',123);check(S.ability.calls==2,'already newer inbound sample recovers')
   for i=1,40 do clock=clock+.01;S.hit:Fire('parry',123);matchPacket(123,{dt=.04,speed=600}) end
   check(S.ability.calls==42,'one shot per proved inbound flight');heartbeat(.1)
   check(peak==20,'20 proved mock cycles per second');c.stop()
  """)

 def test_completed_miss_rearms_same_target_without_repeating_stale_cooldown(self):
  run_case(FIXTURE + parry_runtime() + r"""
   setup();local cd={source='local',blocking=false}
   local c=assert(mod.create({canAct=function() return true end,getCooldown=function() return cd end,
    onAttempt=function(_,at) cd.pressAt=at;cd.blocking=true;cd.miss=false end}))
   matchPacket(123);assert(S.ability.calls==1)
   matchPacket(123);assert(S.ability.calls==1,'blocking cooldown prevents retry')
   cd.miss=true;cd.phase='miss_finished';cd.blocking=false
   S.runs.PostSimulation:Fire();assert(S.ability.calls==2,'completed cooldown retries same target')
   matchPacket(123);assert(S.ability.calls==2,'new attempt locks again')
   cd.blocking=false;cd.miss=true;cd.pressAt=clock-1
   S.runs.PostSimulation:Fire();assert(S.ability.calls==2,'old miss cannot rearm')
   cd.pressAt=clock-.02;cd.lastParriedAt=clock
   S.runs.PostSimulation:Fire();assert(S.ability.calls==2,'successful parry is not retry')
   c.stop()
  """)

 def test_normal_flights_do_not_wait_for_cooldown_or_read_it(self):
  run_case(FIXTURE + parry_runtime() + r"""
   setup();local reads=0
   local c=assert(mod.create({canAct=function() return true end,getCooldown=function()
    reads=reads+1;return {source='local',blocking=true,miss=false} end}))
   matchPacket(123);assert(S.ability.calls==1 and reads==0,'first flight bypasses cooldown lookup')
   matchPacket(456);matchPacket(123)
   assert(S.ability.calls==2 and reads==0,'ordinary return bypasses stale blocking cooldown')
   c.stop()
  """)

 def test_geometry_and_invalid_data(self):
  self.check_lua(r"""
   setup();local c=start();S.ball.Position=vec(1000);matchPacket(123,{distance=8})
   check(S.ability.calls==1,'native trajectory takes precedence over visible ball')
   check(S.native.simulationCalls==1,'radius fast path uses one simulation')
   for i=1,20 do S.runs.PreSimulation:Fire();S.runs.PostSimulation:Fire() end
   check(S.native.simulationCalls==1,'spent episode skips all physics');c.stop()
   setup();c=start();matchPacket(123,{age=.5});matchPacket(123,{position=vec(0/0)});matchPacket(123,{speed=1001})
   check(S.ability.calls==0,'invalid input rejected');c.stop()
   setup();S.gb.clash=true;S.gb.pressure=1;c=start()
   matchPacket(123,{distance=100,speed=600});check(S.ability.calls==0,'pressure narrows server window')
   matchPacket(123,{distance=20,speed=600});check(S.ability.calls==1,'inside pressed window');c.stop()
   setup();c=start();matchPacket(123,{distance=30,speed=16})
   check(published.window==.5,'500ms opening match window');check(S.ability.calls==0,'far slow opening is not early');c.stop()
  """)

 def test_training_remote_and_lifecycle(self):
  self.check_lua(r"""
   setup();local original=S.native.ApplySnapshot;local c=start();trainingMode();trainPacket(123)
   check(S.block.calls==1 and S.ability.calls==0,'training uses Block remote')
   for i=1,10 do trainPacket(123) end
   check(S.block.calls==1,'training does not repeat')
   trainPacket(0);trainPacket(123);check(S.block.calls==2,'training away and return')
   S.training.inZone=false;S.player:SetAttribute('Lives',3);matchPacket(123)
   check(S.ability.calls==1,'match after training')
   S.training.inZone=true;S.player:SetAttribute('Lives',0);heartbeat();trainPacket(123)
   check(S.block.calls==3,'training after match');c.stop()
   check(S.native.ApplySnapshot==original,'native method restored on stop')
   trainPacket(0);trainPacket(123);matchPacket(456);matchPacket(123);S.hit:Fire('parry',123)
   check(S.block.calls==3 and S.ability.calls==1,'stopped instance never sends')
   check(created.ScreenGui==nil,'engine creates no competing UI')
  """)

 def test_hub_policy_is_rechecked_and_training_survives_spam(self):
  self.check_lua(r"""
   setup();local c=start();enabled=false;matchPacket(123);check(S.ability.calls==0,'toggle off')
   enabled=true;spam=true;S.runs.PreSimulation:Fire();check(S.ability.calls==0,'spam owns match dispatch')
   spam=false;S.runs.PostSimulation:Fire();check(S.ability.calls==1,'AP resumes')
   trainingMode();spam=true;trainPacket(123);check(S.block.calls==1,'training policy independent of match spam')
   enabled=false;trainPacket(0);trainPacket(123);check(S.block.calls==1,'toggle stops training');c.stop()
  """)

class HubAdapterTests(unittest.TestCase):
 def test_toggle_rebind_and_single_driver(self):
  run_case(FIXTURE + parry_runtime() + 'local engine=mod\n' + module('autoparry.luau') + r"""
   setup();S.char.AncestryChanged=signal()
   local enabled,spam=true,false;local opportunities,attempts=0,0
   local u={getLocalPlayer=function() return S.player end,getRunService=function() return S.runs end,
    isActive=function() return true end,getConfigValue=function() return enabled end,isSpamActive=function() return spam end,
    trackCharacter=function() end,untrackCharacter=function() end}
   local g={getSnapshotAt=function() return {mode='match',ball=S.ball} end}
   local cd={recordDeflectAttempt=function() attempts=attempts+1 end,recordTrainingDeflectAttempt=function() attempts=attempts+1 end}
   assert(mod.setup({Utils=u,GameInfo=g,Remote={},Cooldown=cd,DefenseEngine=engine,DeflectGeometry={},
    AutoSpam={onDefenseOpportunity=function() opportunities=opportunities+1 end}}))
   local original=S.native.ApplySnapshot
   assert(mod.bindCharacter(S.char));matchPacket(123);assert(S.ability.calls==1 and attempts==1)
   assert(opportunities>0,'old AutoSpam notification retained')
   enabled=false;matchPacket(456);matchPacket(123);assert(S.ability.calls==1)
   enabled=true;S.runs.PostSimulation:Fire();assert(S.ability.calls==2)
   assert(mod.bindCharacter(S.char));matchPacket(456);matchPacket(123);assert(S.ability.calls==3,'rebind has one driver')
   mod.detachCharacter();assert(S.native.ApplySnapshot==original,'detach restores native hook')
   matchPacket(456);matchPacket(123);assert(S.ability.calls==3)
   for _,msg in ipairs(logs) do assert(not msg:find('[AutoParry] ',1,true),msg) end
  """)

if __name__ == '__main__':
 unittest.main()
