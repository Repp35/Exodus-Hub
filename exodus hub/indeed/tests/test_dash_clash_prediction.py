"""Real activation paths, including dash priority and physical rejection cases."""
import unittest
from autospam_harness import check

class DashClashPrediction(unittest.TestCase):
    def test_normal_dash_waits_for_a_real_exchange_with_the_dasher(self):
        check("other.root.Position=v(40);packet(99,0,50);dash(99,-120);heartbeat(.01);assert(not ap.isActive());packet(42,.01,50);assert(ap.isActive() and ap.getActivationContext().reason=='dash_incoming')")
        check("other.root.Position=v(40);dash(99,-120);packet(42,0,50);heartbeat(.01);assert(not ap.isActive() and clicks==0)")

    def test_third_party_exchange_cannot_validate_the_dasher(self):
        check("other.root.Position=v(40);packet(88,0,50);dash(99,-120);packet(42,.01,50);assert(not ap.isActive());packet(99,.01,50);assert(ap.isActive() and ap.getActivationContext().reason=='dash_incoming')")

    def test_self_normal_dash_needs_an_exchange_during_the_dash(self):
        check("other.root.Position=v(40);packet(42,0,50);dash(42,120);packet(99,.01,50);assert(ap.isActive() and ap.getActivationContext().reason=='dash_self')")

    def test_old_exchange_and_wind_dash_do_not_validate_normal_dash(self):
        check("other.root.Position=v(40);packet(99,0,50);packet(42,.01,50);advance(.01);dash(99,-120);heartbeat(.01);assert(not ap.isActive())")
        check("other.root.Position=v(40);packet(99,0,50);dash(99,-120);dashSamples[99].ability='wind';packet(42,.01,50);assert(not ap.isActive())")

    def test_invalid_dash_does_not_start_spam(self):
        for mutation in ("dashSamples[99].signalActive=false","dashSamples[99].velocity=v(120)",
                         "dashSamples[99].observedAt=tm-1","dashSamples[99].normalModel.estimatedRemaining=0",
                         "wall=true","snap.position=v(500)","dashSamples[99].velocity=v(0,120)"):
            with self.subTest(mutation=mutation):
                check("other.root.Position=v(40);dash(99,-120);"+mutation+";packet(42);assert(not ap.isActive() and clicks==0)")


if __name__=='__main__': unittest.main()
