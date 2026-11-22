"""Return activation requires a real fast round trip inside the distance window."""
import unittest
from autospam_harness import check

class ReturnTargetWindow(unittest.TestCase):
    def test_color_alone_and_later_approach_cannot_create_a_return(self):
        check('''
cfg.AutoSpamClashPrediction=false
snap.targetUncertain=true;snap.targetId=-1;snap.position=v(300)
snap.targetSignals={known=false,signals={{name='ball.targetColor',available=true,targeted=true}}}
heartbeat(.01);assert(not ap.isActive())
snap.position=v(10);heartbeat(.01)
assert(not ap.isActive(),'color-only approach activated return_target')
''')

    def test_stale_self_color_cannot_override_confirmed_outgoing_target(self):
        check('''
cfg.AutoSpamClashPrediction=false
packet(42,0,50)
snap.targetSignals={known=true,signals={{name='ball.targetColor',available=true,targeted=true}}}
packet(99,.01,50);heartbeat(.01)
assert(not ap.isActive(),'stale color fabricated a return')
assert(ap.getStatus().confirmedReturns==0)
packet(42,.02,50)
assert(ap.isActive() and ap.getActivationContext().reason=='return_target')
''')

    def test_fast_round_trip_respects_point_eight_full_radius(self):
        for distance, active in ((166, True), (168, False)):
            with self.subTest(distance=distance):
                check(f'''
cfg.AutoSpamClashPrediction=false
packet(42,0,50);packet(99,.01,50);packet(42,.05,{distance})
assert(ap.isActive()=={str(active).lower()})
if ap.isActive() then assert(ap.getActivationContext().reason=='return_target') end
''')

    def test_return_outside_window_cannot_arm_later_approach(self):
        check('''
cfg.AutoSpamClashPrediction=false
packet(42,0,50);packet(99,.01,50);packet(42,.05,300)
assert(not ap.isActive());snap.position=v(10);heartbeat(.01)
assert(not ap.isActive(),'far return became a proximity activation')
''')

    def test_initial_incoming_slow_return_and_third_party_are_not_round_trips(self):
        for events in ("packet(99,0,50);packet(42,.05,10)",
                       "packet(42,0,50);packet(99,.01,50);packet(42,.61,10)",
                       "packet(42,0,50);packet(99,.01,50);packet(88,.01,50);packet(42,.01,10)"):
            with self.subTest(events=events):
                check("cfg.AutoSpamClashPrediction=false;"+events+";assert(not ap.isActive())")
