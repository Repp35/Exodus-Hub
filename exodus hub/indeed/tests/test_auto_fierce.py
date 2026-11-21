"""Fierce uses confirmed current miss and current geometry, without prediction."""
import unittest
from autospam_harness import COMMON, ENGINE
from test_logic_reliability import module, run_case

BOOT = r'''
cfg.AutoFierce=true;snap.position=v(10);snap.targetUncertain=false
cd.miss=true;cd.blocking=true;cd.remaining=1;cd.episode=1
local fired,locks,cancels=0,0,0
local fierce={Cooldown=0,ActivateAndBlock=function() end}
g.getFierceDeflectAbility=function() return fierce end
g.getParrySnapshot=function() error('prediction must not be read') end
local beforeSend
local remote={fireFierce=function(guard) if beforeSend then beforeSend() end;if not guard() then return false end;fired=fired+1;return true end}
local ap={beginFierce=function() locks=locks+1;return {} end,cancelFierce=function() cancels=cancels+1 end,
 getTiming=function() error('AP prediction must not be queried') end}
assert(mod.setup({Utils=u,GameInfo=g,Remote=remote,AutoParry=ap,Cooldown=c,AutoSpam={stopSpam=function() end}}))
local function step() heart:Fire(.016) end
'''
class AutoFierceTests(unittest.TestCase):
 def check(self,case):run_case(COMMON+ENGINE+module('extras/autofierce.luau')+BOOT+case)
 def test_current_miss_activates_immediately_once(self):
  self.check('step();assert(fired==1 and locks==1);step();assert(fired==1)')
 def test_current_non_miss_never_activates(self):
  self.check('cd.miss=false;tm=tm+10;snap.syncAt=tm;step();assert(fired==0)')
 def test_current_target_and_window_are_required(self):
  for change in ('snap.targetId=99','snap.position=v(1000)','snap.targetUncertain=true','frozen=true','snap.locked=true','snap.syncAt=tm-1'):
   with self.subTest(change=change):self.check(change+';step();assert(fired==0)')
 def test_current_cooldown_must_still_be_active(self):
  for change in ('cd.blocking=false','cd.remaining=0','cd.source="unknown"','cd.episode=nil'):
   with self.subTest(change=change):self.check(change+';step();assert(fired==0)')
 def test_current_state_is_rechecked_before_send(self):
  self.check('beforeSend=function() cd.miss=false end;step();assert(fired==0 and locks==0)')
 def test_disabled_or_unavailable_ability(self):
  for change in ('enabled=false','cfg.AutoFierce=false','fierce.Cooldown=1','fierce.IsAvailable=function() return false end'):
   with self.subTest(change=change):self.check(change+';step();assert(fired==0)')
 def test_clash_does_not_block_a_confirmed_miss(self):
  self.check('g.getDefensePhysics=function() return {inClash=true} end;step();assert(fired==1)')
 def test_new_cooldown_episode_can_rescue_again(self):
  self.check('step();cd.episode=2;step();assert(fired==2)')
 def test_teardown_removes_callbacks(self):
  self.check('mod.teardown();step();assert(fired==0)')
if __name__=='__main__':unittest.main()
