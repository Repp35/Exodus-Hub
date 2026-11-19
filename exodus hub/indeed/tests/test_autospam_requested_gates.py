"""Regression tests for independent AutoSpam activation and exit gates."""
import unittest
from autospam_harness import check

class AutoSpamRequestedGates(unittest.TestCase):
    def test_close_activates_without_partner_then_associates_from_exchange(self):
        check('''
other.root.Position=v(80); packet(42,0,5)
assert(ap.isActive()); assert(ap.getActivationContext().partner==-1)
other.root.Position=v(10); packet(99,.01,5)
assert(ap.isActive()); assert(ap.getActivationContext().partner==99)
''')

    def test_auto_has_no_opponent_distance_exit_and_dynamic_keeps_its_own(self):
        check('''
packet(42,0,5);packet(99,.01,5);packet(42,.01,5)
local session=ap.createManualSession(); other.root.Position=v(40)
assert(ap.getManualStopReason(session,0)==nil)
heartbeat(.26); assert(ap.isActive()); assert(ap.getManualStopReason(session,0)=='clash_distance')
''')

    def test_cooldown_near_boundary_updates_while_blocked(self):
        check('''
packet(42,0,5);packet(99,.01,5);packet(42,.01,5)
cd.blocking=true; ap.canSend(); advance(.15); assert(ap.canSend())
other.root.Position=v(17); assert(not ap.canSend()); stopped('cooldown')
''')

    def test_cooldown_range_scales_from_10_to_16_studs(self):
        for speed, distance, stays_active in [(16, 10, True), (16, 11, False), (600, 16, True), (600, 17, False)]:
            with self.subTest(speed=speed, distance=distance):
                check(f'''
snap.syncSpeed={speed};snap.speed={speed};other.root.Position=v({distance})
packet(42,0,5);packet(99,.01,5);packet(42,.01,5)
cd.blocking=true;ap.canSend();advance({0.24 if speed == 16 else 0.15});snap.syncAt=tm
assert(ap.canSend()=={str(stays_active).lower()})
''')

    def test_target_return_timeout_is_independent_of_cooldown(self):
        check('''
packet(42,0,5);packet(99,.01,5); assert(ap.isActive())
advance(.21); snap.syncAt=tm; assert(ap.canSend())
advance(.02); snap.syncAt=tm; assert(not ap.canSend()); stopped('target_return_timeout')
''')

    def test_target_return_resets_timer_and_new_episode_is_independent(self):
        check('''
packet(42,0,5);packet(99,.01,5);advance(.18);packet(42,0,5)
advance(.1);packet(99,0,5);advance(.15);snap.syncAt=tm
assert(ap.canSend()); packet(42,0,5); assert(ap.isActive())
''')

    def test_new_target_event_can_activate_after_stop(self):
        check('''
packet(42,0,5);ap.stopSpam('stop_spam');assert(not ap.isActive())
packet(99,.01,10);packet(42,.50,10);assert(ap.isActive())
''')

    def test_visual_return_without_network_target_or_partner(self):
        check('''
snap.targetUncertain=true;snap.targetId=-1;snap.position=v(10)
snap.targetSignals={known=false,signals={{name='ball.targetColor',available=true,targeted=true}}}
heartbeat(.01); assert(ap.isActive(),ap.getStatus().gates.returnTarget)
assert(ap.getActivationContext().partner==-1); assert(clicks>0)
''')

    def test_prediction_requires_animation(self):
        check('''
g.getDeflectTargetPrediction=function() return 42 end
packet(42,0,10);packet(99,.01,10)
assert(not ap.isActive(),'prediction fired without animation')
animate(99,103); assert(ap.isActive(),ap.getStatus().gates.prediction)
assert(ap.getActivationContext().reason=='extreme_return_prediction')
''')

    def test_confirmed_third_target_is_not_overridden_by_color(self):
        check('''
snap.targetId=88;snap.targeted=false;snap.targetUncertain=false;snap.position=v(10)
snap.targetSignals={known=true,signals={{name='ball.targetColor',available=true,targeted=true}}}
heartbeat(.01);assert(not ap.isActive())
''')

    def test_return_requires_ball_inside_point_eight_window(self):
        for distance, active in [(166, True), (168, False)]:
            with self.subTest(distance=distance):
                check(f'''
packet(42,0,50);packet(99,.01,50);packet(42,.05,{distance})
assert(ap.isActive()=={str(active).lower()})
''')
