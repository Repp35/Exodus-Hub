import unittest
from test_autospam_lifecycle_v6 import AutoSpamLifecycleV6

class DirectionGate(unittest.TestCase):
 def test_departure_blocks_native_reactivation_until_return(self):
  AutoSpamLifecycleV6().case('''
native=true;snap.position=v(5);snap.velocity=v(-600);ap.onDefenseOpportunity(snap);assert(ap.isActive())
snap.position=v(20);snap.velocity=v(600);heartbeat(.016);heartbeat(.016);heartbeat(.016);assert(not ap.isActive())
world.attrs.LastParryAt=tm;world:fireAttr('LastParryAt');heartbeat(.016);assert(not ap.isActive())
snap.position=v(5);snap.velocity=v(-600);snap.targetId=42;world.attrs.LastParryAt=tm;world:fireAttr('LastParryAt');assert(ap.isActive())
''')
