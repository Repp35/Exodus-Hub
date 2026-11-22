import unittest
from autospam_harness import COMMON, ENGINE, API
from test_logic_reliability import module, run_case
from test_autospam_lifecycle_v6 import CONTEXT
NATIVE = CONTEXT

def check(case, extra):
 run_case(COMMON + ENGINE + module('combat/autospam.luau').replace('local mod=', 'local ap=', 1)
  + module('combat/spam.luau').replace('local mod=', 'local spam=', 1) + extra + API + case)


class FastReturn(unittest.TestCase):
 def test_speeds_and_window(self):
  for speed, delay, should in [(16,.149,True),(16,.15,True),(16,.151,True),(600,.149,True),(600,.15,True),(600,.151,True),(308,.149,True),(308,.151,True)]:
   with self.subTest(speed=speed,delay=delay):
    check(f'''snap.speed={speed};snap.syncSpeed={speed};snap.position=v(8);packet(42);packet(99);packet(42,{delay});assert(ap.isActive()=={str(should).lower()});if ap.isActive() then assert(ap.getActivationContext().reason=='fast_return') end''',NATIVE)
 def test_window_and_invalid_target(self):
  check('''snap.speed=600;snap.syncSpeed=600;snap.position=v(150);packet(42);packet(99);packet(42,.05);assert(not ap.isActive())''',NATIVE)
  check('''snap.position=v(8);packet(42);packet(-1);packet(42,.05);assert(not ap.isActive())''',NATIVE)
 def test_slow_ball_inside_06_window_not_09(self):
  check('''snap.speed=16;snap.syncSpeed=16;snap.position=v(20);packet(42);packet(99);packet(42,.05);assert(not ap.isActive())''',NATIVE)
 def test_immediate_first_send(self):
  check('''snap.position=v(8);packet(42);packet(99);packet(42,.05);assert(ap.isActive() and clicks==1)''',NATIVE)
 def test_attributes_are_valid_return_evidence(self):
  check("""snap.position=v(8)
   local function attr(id) ap.onBallSync({Source='target',TargetPlayerID=id}) end
   attr(42);attr(99);attr(42);assert(ap.isActive());assert(clicks==1)""",NATIVE)
 def test_fresh_tight_context_enters_without_waiting_for_pair_packets(self):
  check("""native=true;snap.position=v(8);world:fireAttr("LastParryAt");assert(ap.isActive());assert(clicks==1)""",NATIVE)
 def test_unrelated_attribute_targets_cannot_fake_clash_exchange(self):
  check("""snap.position=v(8);ap.onBallSync({Source='target',TargetPlayerID=88});ap.onBallSync({Source='target',TargetPlayerID=99});assert(not ap.isActive())""",NATIVE)
 def test_clash_pair_must_match_targetid_exchange(self):
  check('''snap.position=v(8);packet(42);packet(99);packet(42,.5);assert(not ap.isActive())
   third.root.Position=v(10000)
   g.getClashStatus=function() return {active=true,partnerId=88,age=.1,lastParryAt=world.attrs.LastParryAt} end
   native=true;world:fireAttr("LastParryAt");assert(not ap.isActive())''',NATIVE)
 def test_tight_clash_can_enter_without_local_target_history(self):
  check('''snap.position=v(8);snap.targetId=99;snap.targeted=false
   g.getClashStatus=function() return {active=true,partnerId=99,age=.1} end
   ap.onDefenseOpportunity(snap);assert(ap.isActive());assert(ap.getActivationContext().reason=='native_clash')''',NATIVE)
 def test_tight_clash_rejects_age_distance_and_large_window(self):
  for condition in ('other.root.Position=v(10000)', 'snap.position=v(10000)', 'snap.targetId=88'):
   with self.subTest(condition=condition):
    check('''local age=.1;snap.position=v(8);snap.targetId=99;snap.targeted=false
     g.getClashStatus=function() return {active=true,partnerId=99,age=age} end
     '''+condition+''';ap.onDefenseOpportunity(snap);assert(not ap.isActive())''',NATIVE)
 def test_retreating_opponent_does_not_add_a_contact_gate_to_native_clash(self):
  check('''snap.speed=200;snap.syncSpeed=200;snap.velocity=v(200);snap.position=v(9)
   other.root.Position=v(20);other.root.AssemblyLinearVelocity=v(180)
   packet(42);packet(99,.2);native=true
   ap.onDefenseOpportunity(snap);assert(ap.isActive(),'native clash must not wait for contact')
   other.root.AssemblyLinearVelocity=v(0)
   ap.onDefenseOpportunity(snap);assert(ap.isActive(),'stationary contact opportunity activates in same callback')''',NATIVE)
 def test_ball_toward_self_can_activate_native_clash(self):
  check('''snap.speed=200;snap.syncSpeed=200;snap.velocity=v(-200);snap.position=v(9)
   other.root.Position=v(20);packet(42);packet(99,.2);native=true
   ap.onDefenseOpportunity(snap);assert(ap.isActive())''',NATIVE)
 def test_native_clash_does_not_require_five_stud_contact_margin(self):
  check('''snap.speed=600;snap.syncSpeed=600;snap.velocity=v(600);snap.position=v(6)
   other.root.Position=v(20);packet(42);packet(99,.2);native=true
   ap.onDefenseOpportunity(snap);assert(ap.isActive(),'valid native clash starts before opponent contact')
   snap.position=v(7);ap.onDefenseOpportunity(snap);assert(ap.isActive())''',NATIVE)
if __name__=='__main__':unittest.main()
