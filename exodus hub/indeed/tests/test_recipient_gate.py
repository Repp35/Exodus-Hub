import unittest
import test_autospam_lifecycle_v6 as lifecycle

class RecipientGate(unittest.TestCase):
 def case(self, script):
  lifecycle.AutoSpamLifecycleV6().case(script)
 def test_far_recipient_blocks_native_and_new_native_attributes(self):
  self.case('''native=true;snap.position=v(5);snap.velocity=v(-600);ap.onDefenseOpportunity(snap);assert(ap.isActive())
snap.position=v(22);snap.velocity=v(600);ap.onDefenseOpportunity(snap);assert(not ap.isActive())
for i=1,5 do advance(.016);world.attrs.LastParryAt=tm;snap.syncAt=tm;ap.onDefenseOpportunity(snap);assert(not ap.isActive()) end
''')
 def test_foreign_round_trip_blocks_even_with_near_players(self):
  self.case('''other.root.Position=v(10);third.root.Position=v(18);native=false;snap.velocity=v(600)
packet(99,0,12);packet(88,.01,12);packet(99,.01,12)
native=true;world.attrs.LastParryAt=tm;ap.onDefenseOpportunity(snap);assert(not ap.isActive());assert(ap.getStatus().gates.common=='other_players_clashing')
''')
 def test_new_local_fast_return_recovers_without_fixed_wait(self):
  self.case('''native=true;snap.position=v(5);snap.velocity=v(-600);ap.onDefenseOpportunity(snap);assert(ap.isActive())
snap.position=v(22);snap.velocity=v(600);ap.onDefenseOpportunity(snap);assert(not ap.isActive())
snap.velocity=v(-600);packet(42,.01,5);packet(99,.01,5);packet(42,.01,5);assert(ap.isActive())
''')
 def test_foreign_round_trip_is_detected_without_local_distance_limit(self):
  self.case('''other.root.Position=v(150);third.root.Position=v(170);native=false;snap.velocity=v(600)
packet(99,0,160);packet(88,.01,160);packet(99,.01,160)
other.root.Position=v(10);third.root.Position=v(18);snap.position=v(12);snap.syncAt=tm;native=true
ap.onDefenseOpportunity(snap);assert(not ap.isActive());assert(ap.getStatus().gates.common=='other_players_clashing')
''')
 def test_opponent_behind_can_start_new_local_fast_exchange(self):
  self.case('''native=true;snap.position=v(5);snap.velocity=v(-600);ap.onDefenseOpportunity(snap);assert(ap.isActive())
snap.position=v(22);snap.velocity=v(600);ap.onDefenseOpportunity(snap);assert(not ap.isActive())
other.root.Position=v(-10);snap.velocity=v(600)
packet(42,.01,-5);packet(99,.01,-5);packet(42,.01,-5);assert(ap.isActive())
''')
