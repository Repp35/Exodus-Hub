"""Regression scenarios for the production AutoSpam and the real spam scheduler.

Mocks supply game/network observations; no server acceptance or live FPS claims.
"""
import unittest
from autospam_harness import COMMON, ENGINE, API
from test_logic_reliability import module, run_case

CONTEXT = '''
local native=false
local attributeSignals={}
function world:GetAttributeChangedSignal(name)
 if not attributeSignals[name] then attributeSignals[name]=signal() end
 return attributeSignals[name]
end
function world:fireAttr(name) self:GetAttributeChangedSignal(name):Fire() end
world.attrs.LastParryAt=tm
world.attrs.LastParryBy=99
world.attrs.LastParryTarget=42
g.getClashStatus=function()
 return {active=native,partnerId=99,lastParryAt=world.attrs.LastParryAt,age=tm-world.attrs.LastParryAt,maxAge=.8}
end
'''

class AutoSpamLifecycleV6(unittest.TestCase):
 def case(self,script):
  run_case(COMMON + ENGINE + module('autospam.luau').replace('local mod=', 'local ap=', 1)
   + module('spam.luau').replace('local mod=', 'local spam=', 1) + CONTEXT + API + script)
 def test_immediate_native_activation_dispatches_before_next_frame(self):
  self.case('native=true;snap.position=v(5);ap.onDefenseOpportunity(snap);assert(ap.isActive());assert(clicks==1)')
 def test_ordinary_approach_after_own_parry_does_not_start_spam(self):
  self.case('native=false;world.attrs.LastParryBy=42;snap.position=v(5);ap.onDefenseOpportunity(snap);assert(not ap.isActive());assert(clicks==0)')
 def test_packet_round_trip_does_not_require_clash_attributes(self):
  self.case('packet(42,0,5);packet(99,.01,5);packet(42,.02,5);assert(ap.isActive());assert(clicks==1)')
 def test_snapshot_observation_before_packet_does_not_lose_target_edges(self):
  self.case('''
local function deliver(id)
 advance(.01);snap.targetId=id;snap.targeted=id==42;snap.syncAt=tm;snap.syncSequence=snap.syncSequence+1
 ap.onDefenseOpportunity(snap)
 ap.onBallSync({Source='packet',Sequence=snap.syncSequence,TargetPlayerID=id,Speed=600})
end
deliver(42);snap.position=v(5);deliver(99);deliver(42);assert(ap.isActive());assert(clicks==1)
''')
 def test_attribute_only_round_trip_activates(self):
  self.case('''snap.position=v(5)
for _,id in ipairs({42,99,42}) do advance(.01);snap.syncAt=tm;ap.onBallSync({Source='target',TargetPlayerID=id}) end
assert(ap.isActive());assert(clicks==1)''')
 def test_packet_and_attribute_echo_do_not_duplicate_an_activation(self):
  self.case('''packet(42,0,5);ap.onBallSync({Source='target',TargetPlayerID=42})
packet(99,.01,5);ap.onBallSync({Source='target',TargetPlayerID=99})
packet(42,.02,5);local n=clicks;ap.onBallSync({Source='target',TargetPlayerID=42});ap.onDefenseOpportunity(snap)
assert(ap.isActive());assert(clicks==n)
local count=0;for _,t in ipairs(transitions) do if t[3]=='active' then count=count+1 end end;assert(count==1)''')
 def test_delayed_entry_preserves_return_evidence(self):
  self.case('packet(42,0,500);packet(99,.01,500);packet(42,.02,150);assert(not ap.isActive());snap.position=v(5);heartbeat(.01);assert(ap.isActive())')
 def test_return_evidence_expires(self):
  self.case('packet(42,0,500);packet(99,.01,500);packet(42,.02,150);heartbeat(.8);snap.position=v(5);heartbeat(.01);assert(not ap.isActive())')
 def test_151ms_return_is_not_rejected_by_fixed_150ms_cutoff(self):
  self.case('packet(42,0,5);packet(99,.01,5);packet(42,.151,5);assert(ap.isActive())')
 def test_current_native_clash_can_reactivate_after_geometry_exit(self):
  self.case('''native=true;snap.position=v(5);ap.onDefenseOpportunity(snap);assert(ap.isActive())
snap.position=v(500);ap.onDefenseOpportunity(snap);assert(not ap.isActive())
snap.position=v(5);heartbeat(.01);assert(ap.isActive());assert(ap.getStatus().gates.native=='ready')''')
 def test_new_parry_rearms_immediately_without_fixed_pause(self):
  self.case('''native=true;snap.position=v(5);ap.onDefenseOpportunity(snap);snap.position=v(500);ap.onDefenseOpportunity(snap)
advance(.001);world.attrs.LastParryAt=tm;snap.syncAt=tm;snap.position=v(5);ap.onDefenseOpportunity(snap);assert(ap.isActive())''')
 def test_native_anticipation_can_resume_without_local_target(self):
  self.case('''native=true;snap.targetId=99;snap.targeted=false;snap.position=v(10);snap.velocity=v(600)
ap.onDefenseOpportunity(snap);assert(ap.isActive());snap.position=v(500);ap.onDefenseOpportunity(snap)
snap.position=v(10);heartbeat(.01);assert(ap.isActive())''')
 def test_outward_leg_toward_partner_does_not_stop_clash(self):
  self.case('''native=true;snap.position=v(5);ap.onDefenseOpportunity(snap)
packet(99,.01,5);snap.velocity=v(600);assert(ap.canSend());assert(ap.isActive())''')
 def test_leaving_both_players_stops_before_next_send(self):
  self.case('''native=true;snap.position=v(5);ap.onDefenseOpportunity(snap)
other.root.Position=v(25);snap.position=v(60);snap.velocity=v(600);snap.targetId=99
local n=clicks;assert(not ap.canSend());assert(not ap.isActive());advance(.1);assert(clicks==n)''')
 def test_ball_above_both_players_cannot_keep_sending_during_clash(self):
  self.case('''native=true;snap.position=v(5);ap.onDefenseOpportunity(snap);assert(ap.isActive())
snap.position=v(5,20);snap.velocity=v(600);snap.targetId=99
local n=clicks;assert(not ap.canSend(),'trajectory missed both players but sending stayed authorized')
assert(not ap.isActive());advance(.1);assert(clicks==n)''')
 def test_confirmed_third_target_stops_before_send(self):
  self.case('native=true;snap.position=v(5);ap.onDefenseOpportunity(snap);snap.targetId=88;snap.targetUncertain=false;assert(not ap.canSend());assert(not ap.isActive())')
 def test_fast_return_cannot_override_confirmed_miss(self):
  self.case('''native=true;snap.position=v(5);ap.onDefenseOpportunity(snap)
cd.blocking=true;cd.miss=true;cd.episode=1;cd.blockingSince=tm;heartbeat(.3);assert(not ap.isActive())
packet(42,.01,5);packet(99,.01,5);packet(42,.01,5);assert(not ap.isActive());assert(ap.getStatus().gates.common=='miss_cooldown')
cd.blocking=false;ap.onDefenseOpportunity(snap);assert(ap.isActive())''')
 def test_fast_return_does_not_reset_a_timed_out_cooldown_episode(self):
  self.case('''native=true;snap.position=v(5);ap.onDefenseOpportunity(snap)
cd.blocking=true;cd.miss=false;cd.episode=1;cd.blockingSince=tm;heartbeat(.3);assert(not ap.isActive(),'did not stop');assert(ap.getStatus().lastStopReason=='cooldown')
packet(42,.01,5);packet(99,.01,5);packet(42,.01,5);assert(not ap.isActive(),'reactivated during timed cooldown')
cd.blocking=false;ap.onDefenseOpportunity(snap);assert(ap.isActive(),'did not rearm after ready')''')
 def test_reversible_cooldown_does_not_cut_legitimate_return(self):
  self.case('cd.blocking=true;cd.miss=false;cd.predictedReset=true;packet(42,0,5);packet(99,.01,5);packet(42,.01,5);assert(ap.isActive())')
 def test_cooldown_duration_cannot_be_reset_by_parry_or_prediction_or_miss_flags(self):
  self.case('''native=true;snap.position=v(5);ap.onDefenseOpportunity(snap)
cd.blocking=true;cd.miss=false;cd.predictedReset=true;cd.episode=1;cd.blockingSince=tm
assert(ap.canSend())
advance(.1);cd.lastParriedAt=tm;assert(ap.canSend())
advance(.13);cd.lastParriedAt=tm
assert(not ap.canSend(),'active cooldown exceeded its duration but another flag prevented stop')
assert(ap.getStatus().lastStopReason=='cooldown')''')
 def test_slow_ball_stops_on_first_check_after_cooldown_time_limit(self):
  self.case('''native=true;snap.position=v(5);ap.onDefenseOpportunity(snap)
cd.blocking=true;cd.miss=false;cd.blockingSince=tm
snap.syncSpeed=16;snap.speed=16;snap.velocity=v(-16)
assert(ap.canSend());advance(.346)
local n=clicks;assert(not ap.canSend());assert(not ap.isActive());assert(clicks==n)''')
 def test_old_packet_cannot_create_round_trip(self):
  self.case('packet(42,0,5,10);packet(99,.01,5,11);packet(42,.01,5,10);assert(not ap.isActive())')
 def test_duplicate_packet_cannot_create_round_trip(self):
  self.case('packet(42,0,5,10);packet(99,.01,5,11);packet(42,.01,5,11);assert(not ap.isActive())')
 def test_freeze_config_death_and_detach_cancel_sends(self):
  for change in ['frozen=true','cfg.AutoSpam=false','me.hum.Health=0','other.hum.Health=0']:
   with self.subTest(change=change):self.case('native=true;snap.position=v(5);ap.onDefenseOpportunity(snap);'+change+';assert(not ap.canSend());assert(not ap.isActive())')
  self.case('native=true;snap.position=v(5);ap.onDefenseOpportunity(snap);ap.detachCharacter();local n=clicks;heartbeat();assert(clicks==n);assert(not ap.isActive())')
 def test_explicit_unknown_target_invalidates_previous_return_leg(self):
  self.case('packet(42,0,5);packet(99,.01,5);packet(-1,.01,5);packet(42,.01,5);assert(not ap.isActive())')
 def test_sequence_wrap_is_ordered(self):
  self.case('packet(42,0,5,32767);packet(42,0,5,65534);packet(99,.01,5,65535);packet(42,.01,5,0);assert(ap.isActive())')

if __name__=='__main__':unittest.main()
