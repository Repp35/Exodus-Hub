import unittest
from test_native_clash_activation import check, NATIVE

class FastReturn(unittest.TestCase):
 def test_speeds_and_window(self):
  for speed, delay, should in [(16,.149,True),(16,.15,True),(16,.151,False),(600,.149,True),(600,.15,True),(600,.151,False),(308,.149,True),(308,.151,False)]:
   with self.subTest(speed=speed,delay=delay):
    check(f'''snap.speed={speed};snap.syncSpeed={speed};snap.position=v(8);packet(42);packet(99);packet(42,{delay});assert(ap.isActive()=={str(should).lower()});if ap.isActive() then assert(ap.getActivationContext().reason=='fast_return') end''',NATIVE)
 def test_window_and_invalid_target(self):
  check('''snap.speed=600;snap.syncSpeed=600;snap.position=v(150);packet(42);packet(99);packet(42,.05);assert(not ap.isActive())''',NATIVE)
  check('''snap.position=v(8);packet(42);packet(-1);packet(42,.05);assert(not ap.isActive())''',NATIVE)
 def test_slow_ball_inside_06_window_not_09(self):
  check('''snap.speed=16;snap.syncSpeed=16;snap.position=v(20);packet(42);packet(99);packet(42,.05);assert(not ap.isActive())''',NATIVE)
 def test_immediate_first_send(self):
  check('''snap.position=v(8);packet(42);packet(99);packet(42,.05);assert(ap.isActive() and clicks==1)''',NATIVE)
 def test_attributes_cannot_create_fast_return(self):
  check('''snap.position=v(8)
   local function attr(id) ap.onBallSync({Source='target',TargetPlayerID=id}) end
   attr(42);attr(99);attr(42);assert(not ap.isActive())
   packet(42);packet(99);attr(42);assert(not ap.isActive())
   packet(42,.05);assert(ap.isActive(),'only network target return activates')''',NATIVE)
 def test_clash_requires_one_targetid_switch_in_either_direction(self):
  for first,second in [(42,99),(99,42)]:
   with self.subTest(first=first):
    check(f'''native=true;snap.position=v(8);world.changed:Fire();assert(not ap.isActive(),'proximity alone cannot activate')
     packet({first});assert(not ap.isActive(),'one target alone cannot activate')
     packet({second},.2);assert(ap.isActive(),'one pair switch permits clash entry')
     assert(ap.getActivationContext().reason=='native_clash')''',NATIVE)
 def test_attributes_cannot_fake_clash_exchange(self):
  check('''native=true;snap.position=v(8)
   ap.onBallSync({Source='target',TargetPlayerID=42});ap.onBallSync({Source='target',TargetPlayerID=99})
   assert(not ap.isActive());packet(99);assert(not ap.isActive());packet(42,.2);assert(ap.isActive())''',NATIVE)
 def test_clash_pair_must_match_targetid_exchange(self):
  check('''snap.position=v(8);packet(42);packet(99);packet(42,.2);assert(not ap.isActive())
   g.getClashStatus=function() return {active=true,partnerId=88} end
   native=true;world.changed:Fire();assert(not ap.isActive())''',NATIVE)
if __name__=='__main__':unittest.main()
