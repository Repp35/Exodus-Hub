import unittest
import test_autospam_lifecycle_v6 as lifecycle

class LiveActivationGates(unittest.TestCase):
 def test_non_target_native_clash_can_reactivate_after_departure(self):
  lifecycle.AutoSpamLifecycleV6().case('''
native=true;snap.position=v(5);snap.velocity=v(-600);ap.onDefenseOpportunity(snap);assert(ap.isActive())
snap.position=v(22);snap.velocity=v(600);ap.onDefenseOpportunity(snap);assert(not ap.isActive())
advance(.01);snap.syncAt=tm;snap.position=v(5);snap.velocity=v(600);snap.targetId=99
world.attrs.LastParryAt=tm;world.attrs.LastParryBy=42;world.attrs.LastParryTarget=99
ap.onDefenseOpportunity(snap);assert(ap.isActive(),'valid outward clash was blocked by past departure')
''')
 def test_current_departure_blocks_even_fresh_native_clash(self):
  lifecycle.AutoSpamLifecycleV6().case('''
native=true;snap.position=v(22);snap.velocity=v(600);snap.targetId=99
for i=1,4 do advance(.01);snap.syncAt=tm;world.attrs.LastParryAt=tm;ap.onDefenseOpportunity(snap);assert(not ap.isActive()) end
''')
