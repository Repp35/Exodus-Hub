"""One bounded early burst at extreme contact, confirmed only by a real exchange."""
import unittest
from autospam_harness import check

class ExtremeContact(unittest.TestCase):
    def test_starts_before_local_target_and_continues_after_exchange(self):
        check('''
other.root.Position=v(4.4);snap.syncSpeed=83;snap.speed=83;snap.velocity=v(-83)
packet(99,0,15);assert(ap.isActive() and clicks>0,'did not pre-arm before target receipt')
assert(ap.getActivationContext().reason=='extreme_return_prediction')
packet(42,.05,5);heartbeat(.3);assert(ap.isActive(),'confirmed exchange did not preserve spam')
''')

    def test_unconfirmed_attempt_expires_and_cannot_loop_on_same_leg(self):
        check('''
other.root.Position=v(4);packet(99,0,12);assert(ap.isActive())
heartbeat(.241);stopped('anticipation_expired')
for i=1,10 do packet(99,.02,12) end
assert(not ap.isActive(),'unconfirmed leg retriggered speculative burst')
''')

    def test_redirection_preserves_immediate_stop(self):
        check('''
other.root.Position=v(4);packet(99,0,12);assert(ap.isActive())
packet(88,.01,12);assert(not ap.isActive(),'third target did not cancel anticipation')
''')

    def test_distance_and_arrival_gates_keep_normal_gameplay(self):
        for setup in ('other.root.Position=v(6);packet(99,0,12)',
                      'other.root.Position=v(4);packet(99,0,300)',
                      'other.root.Position=v(4);snap.velocity=v(600);packet(99,0,50)',
                      'other.root.Position=v(4);snap.locked=true;packet(99,0,12)'):
            with self.subTest(setup=setup):
                check(setup+';assert(not ap.isActive())')
