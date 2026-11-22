"""Real target transitions survive provider callbacks and transient render gaps."""
import unittest
from autospam_harness import check

class ConfirmedExchanges(unittest.TestCase):
    def test_replicator_events_activate_without_raw_remote_callback(self):
        check('''
local function provider(target,dt)
 advance(dt);snap.syncSequence=snap.syncSequence+1;snap.targetId=target;snap.syncAt=tm
 ap.onBallSync({Source='replicator',Sequence=snap.syncSequence,TargetPlayerID=target})
end
provider(42,0);provider(99,.02);provider(42,.05)
assert(ap.isActive() and clicks>0,'accepted provider exchange was ignored')
''')

    def test_transient_position_disagreement_does_not_erase_real_round_trip(self):
        check('''
snap.realPosition=v(500)
packet(42,0,50);packet(99,.02,50);packet(42,.05,50)
assert(not ap.isActive(),'invalid position bypassed common gate')
snap.realPosition=v(50);heartbeat(.01)
assert(ap.isActive(),'valid round trip was lost during temporary physics disagreement')
''')

    def test_four_switches_in_range_are_not_vetoed_by_outgoing_visual_velocity(self):
        check('''
snap.velocity=v(600)
packet(42,0,100);packet(99,.02,100);packet(42,.05,100)
assert(not ap.isActive(),'one unconfirmed return bypassed direction check')
packet(99,.02,100);packet(42,.05,100)
assert(ap.isActive() and ap.getStatus().confirmedReturns==2,'four real switches failed to activate')
''')

    def test_third_party_and_outside_geometry_do_not_build_false_confirmation(self):
        check('''
snap.velocity=v(600)
packet(42,0,100);packet(99,.02,100);packet(42,.05,100)
packet(99,.02,100);packet(88,.01,100);packet(42,.05,100)
assert(not ap.isActive(),'third party completed another players exchange')
for i=1,3 do packet(99,.02,1000);packet(42,.05,1000) end
assert(not ap.isActive(),'exchange history bypassed geometric range')
''')
