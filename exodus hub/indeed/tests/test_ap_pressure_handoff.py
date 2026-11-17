"""Real AutoSpam/Spam: anticipate service saturation, not just lethal contact."""
import unittest
from autospam_harness import check
import test_adaptive_parry as adaptive

class PressureHandoff(unittest.TestCase):
    def test_predict_next_cycle_while_current_return_has_time(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(50);packet(42,0,100)
local r=ap.getStatus().risk
assert(r.deadline>r.response+.04,'fixture already lethal')
assert(ap.isActive() and r.reason=='return_demand_exceeds_ap')
assert(r.requiredCps>4.73 and clicks>0,'spam failed to take over')''')

    def test_two_late_parries_predict_shrinking_headroom(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(60);packet(42,0,100);assert(not ap.isActive())
defense.lastAcceptedSample={at=tm,ball=ball,headroom=.35,distance=30,idealDistance=50}
heartbeat(.01);assert(not ap.isActive())
defense.lastAcceptedSample={at=tm,ball=ball,headroom=.27,distance=22,idealDistance=50}
heartbeat(.01);local r=ap.getStatus().risk
assert(r.deadline>r.response+.04 and r.nextHeadroom<r.response)
assert(ap.isActive() and r.reason=='parry_margin_shrinking')''')

    def test_target_round_trip_trend_anticipates_next_local_return(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(80);packet(42,0,100)
packet(99,.1);packet(42,.22);assert(not ap.isActive(),'320ms cycle should fit')
packet(99,.1);packet(42,.17);local r=ap.getStatus().risk
assert(r.observedCycle>.26 and r.nextCycle<.23,'local cycle trend missing')
assert(ap.isActive() and r.reason=='return_demand_exceeds_ap')''')

    def test_one_target_leg_is_not_a_local_roundtrip(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(80);packet(42,0,100);packet(99,.05)
assert(ap.getStatus().risk.observedCycle==nil,'one leg counted as local demand')''')

    def test_old_late_sample_cannot_trigger_a_new_clash(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(80);defense.lastAcceptedSample={at=tm-1,ball=ball,headroom=.001}
packet(42,0,100);assert(not ap.isActive(),'expired lateness contaminated new episode')''')

    def test_first_fast_approach_needs_no_history(self):
        for own, other in [(0,-120),(120,0),(-16,-120)]:
            check(f'''me.root.AssemblyLinearVelocity=v({own});other.root.AssemblyLinearVelocity=v({other})
other.root.Position=v(60);packet(42,0,150)
assert(ap.isActive(),'dash/approach needed completed cycles')''')

    def test_imminent_incoming_does_not_require_a_nearby_sender(self):
        check('''other.root.Position=v(100);third.root.Position=v(150)
packet(42,0,80);assert(ap.isActive(),'distance gate blocked imminent first receipt')''')

    def test_missing_partner_is_safe(self):
        check('''other.hum.Health=0;third.hum.Health=0
packet(42,0,500);assert(not ap.isActive())''')

    def test_stable_recovery_returns_control_to_ap(self):
        check('''packet(42,0,40);assert(ap.isActive())
packet(42,.01,500);heartbeat(.1);assert(ap.isActive(),'released on one safe sample')
heartbeat(.16);assert(not ap.isActive(),'failed to return control after stable recovery')
assert(ap.getStatus().lastStopReason=='ap_recovered')''')

    def test_pressure_resets_recovery_hysteresis(self):
        check('''packet(42,0,40);packet(42,.01,500);heartbeat(.2)
packet(42,.01,40);packet(42,.01,500);heartbeat(.1)
assert(ap.isActive(),'old safe timer released during renewed pressure')''')

    def test_real_ap_reports_reference_and_dispatch_headroom(self):
        adaptive.AdaptiveParry().check('''
gameBall.ApplyClashPressureGrace=function() return .02 end
clashing=true;pressure=1;publish(8,600);frame:Fire(1/60)
local d=ap.getDefenseState(gi.getParrySnapshot(tm))
assert(d.responseBudget>=1/4.73 and d.pressureReferenceCps==4.73)
assert(d.lastAcceptedSample and d.lastAcceptedSample.distance>4)
assert(d.lastAcceptedSample.ball==ball and d.lastAcceptedSample.headroom<d.responseBudget)
''')

if __name__=='__main__': unittest.main()
