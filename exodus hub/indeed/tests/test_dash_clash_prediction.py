"""Real activation paths, including dash priority and physical rejection cases."""
import unittest
from autospam_harness import check

class DashClashPrediction(unittest.TestCase):
    def test_dash_is_first_and_needs_no_target_exchange(self):
        check('''
other.root.Position=v(40);dash(99,-120);packet(42,0,50)
assert(ap.isActive() and clicks==1);assert(ap.getActivationContext().reason=='dash_incoming')
''')
        check("dash(99,-120);packet(42,0,2);assert(ap.getActivationContext().reason=='dash_incoming')")

    def test_new_dasher_is_not_hidden_by_previous_opponent(self):
        check("packet(88,0,50);dash(99,-120);packet(42,.01);assert(ap.getActivationContext().reason=='dash_incoming')")

    def test_self_dash_activates(self):
        check("other.root.Position=v(40);packet(99,0,50);dash(42,120);heartbeat(.01);assert(ap.getActivationContext().reason=='dash_self')")

    def test_invalid_dash_does_not_start_spam(self):
        for mutation in ("dashSamples[99].signalActive=false","dashSamples[99].velocity=v(120)",
                         "dashSamples[99].observedAt=tm-1","dashSamples[99].normalModel.estimatedRemaining=0",
                         "wall=true","snap.position=v(500)","dashSamples[99].velocity=v(0,120)"):
            with self.subTest(mutation=mutation):
                check("other.root.Position=v(40);dash(99,-120);"+mutation+";packet(42);assert(not ap.isActive() and clicks==0)")


if __name__=='__main__': unittest.main()
