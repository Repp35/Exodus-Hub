"""The added gate needs exchange evidence; pre-existing gates remain independent."""
import unittest
from autospam_harness import check

class ExchangeGate(unittest.TestCase):
    def test_near_spawn_is_not_return_evidence_at_any_speed(self):
        for speed in (16,100,300,600):
            for distance in (5,10,30):
                with self.subTest(speed=speed,distance=distance):
                    check(f'''snap.speed={speed};snap.syncSpeed={speed};snap.velocity=v(-{speed})
packet(42,0,{distance});for i=1,8 do heartbeat(.02) end
local risk=ap.getStatus().risk
assert(not risk.exchangeEvidence and not risk.risky,'spawn invented an exchange')
assert(not ap.isActive(),'added gate or fallback activated on spawn')''')

    def test_original_instant_close_gate_is_preserved(self):
        check('''packet(42,0,2)
assert(ap.isActive() and ap.getActivationContext().reason=='close_target')
assert(not ap.getStatus().risk.risky,'added gate stole legacy activation')''')

    def test_nearby_opponent_does_not_imply_immediate_redirect(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(50);packet(42,0,100)
assert(not ap.isActive() and not ap.getStatus().risk.risky)''')

    def test_real_return_trend_still_anticipates_next_exchange(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(80);packet(42,0,100)
packet(99,.1);packet(42,.22);assert(not ap.isActive())
packet(99,.1);packet(42,.17);local risk=ap.getStatus().risk
assert(ap.isActive() and risk.reason=='return_demand_exceeds_ap')
assert(risk.observedCycle>.26 and risk.nextCycle<.23)
assert(risk.deadline>risk.response+.04,'waited for present lethal deadline')''')

    def test_real_late_ap_after_exchange_triggers_takeover(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(60);packet(99,0,100);packet(42,.01,100)
defense.lastAcceptedSample={ball=ball,at=tm,headroom=.35};heartbeat(.01)
assert(not ap.isActive())
defense.lastAcceptedSample={ball=ball,at=tm,headroom=.27};heartbeat(.01)
assert(ap.isActive() and ap.getStatus().risk.reason=='parry_margin_shrinking')''')

    def test_pause_clears_only_added_gate_evidence(self):
        check('''other.root.Position=v(80);packet(42,0,500);packet(99,.1,500)
assert(ap.getStatus().risk.exchangeEvidence)
snap.locked=true;heartbeat(.01);snap.locked=false
packet(42,.01,5);assert(not ap.getStatus().risk.risky)
assert(not ap.getStatus().risk.exchangeEvidence,'pause reused old exchange')''')

    def test_respawn_with_same_instance_drops_old_samples(self):
        check('''other.root.Position=v(80);packet(42,0,500);packet(99,.1,500)
defense.lastAcceptedSample={at=tm,ball=ball,headroom=.01}
snap.speed=0;snap.syncSpeed=0;snap.velocity=v();heartbeat(.02)
snap.speed=600;snap.syncSpeed=600;snap.velocity=v(-600)
packet(42,.01,5);assert(not ap.getStatus().risk.risky)
assert(not ap.getStatus().risk.exchangeEvidence)''')

    def test_expired_fast_leg_does_not_create_new_pressure(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(80);packet(42,0,500);packet(99,.1,500);packet(42,.05,500)
assert(not ap.isActive());heartbeat(.8)
packet(99,.01,100);assert(not ap.getStatus().risk.risky,'expired leg was reused')''')

if __name__=='__main__':unittest.main()
