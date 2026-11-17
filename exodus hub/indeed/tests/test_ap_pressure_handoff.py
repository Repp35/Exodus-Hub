"""The pressure feature is an activation candidate; AP only exposes raw observations."""
import unittest
from autospam_harness import check
import test_adaptive_parry as adaptive

class PressureHandoff(unittest.TestCase):
    def test_late_current_ap_with_safe_next_exchange_does_not_double_click(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(80);packet(99,0,500);packet(42,.01,100)
assert(not ap.isActive())
-- Model the precise AP dispatch for the current visit, after AutoSpam evaluated.
clicks=clicks+1
snap.position=v(20)
defense.lastAcceptedSample={at=tm,ball=ball,distance=20,speed=300,closingSpeed=300}
for i=1,8 do heartbeat(.01) end
assert(clicks==1,'current AP dispatch was followed by an extra spam click')
assert(not ap.isActive() and not ap.getStatus().risk.risky)
assert(ap.getStatus().risk.nextHeadroom<.1,'fixture was not a late AP click')''')

    def test_current_near_ball_is_not_next_exchange_pressure(self):
        check('''other.root.Position=v(100);snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
packet(99,0,500);packet(42,.01,10)
assert(not ap.isActive(),'current proximity triggered extra click without next-return pressure')''')

    def test_real_return_trend_activates_before_next_demand_exceeds_capacity(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(80);packet(42,0,100)
packet(99,.1);packet(42,.22);assert(not ap.isActive())
packet(99,.1);packet(42,.17);local r=ap.getStatus().risk
assert(r.observedCycle>.26 and r.nextCycle<.23)
assert(ap.isActive() and r.reason=='return_demand_exceeds_ap')
assert(clicks==1,'activation produced more than one initial request')
-- Loader evaluates AutoSpam first; the unchanged AP guard sees spam active.
if not u.isAutoSpamActive() then clicks=clicks+1 end
assert(clicks==1,'AP and spam both dispatched for the same handoff')''')

    def test_late_ap_only_matters_when_next_geometry_is_also_dangerous(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(50);packet(99,0,500);packet(42,.01,100)
defense.lastAcceptedSample={at=tm,ball=ball,distance=14,speed=300,closingSpeed=300}
heartbeat(.01)
assert(ap.isActive() and ap.getStatus().risk.reason=='parry_margin_shrinking')''')

    def test_added_gate_does_not_install_recovery_or_restart_controller(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(80);packet(42,0,100)
packet(99,.1);packet(42,.22);packet(99,.1);packet(42,.17)
assert(ap.isActive());other.root.Position=v(10)
packet(42,.01,500)
for i=1,6 do heartbeat(.05);assert(ap.isActive(),'new gate stopped existing spam session') end
local starts=0
for _,t in ipairs(transitions) do if t[1]=='AutoSpam' and t[3]=='active' then starts=starts+1 end end
assert(starts==1,'detector created extra activation bursts')''')

    def test_client_cooldown_is_not_a_clash_end_signal(self):
        check('''packet(42,0,2);assert(ap.isActive());cd.blocking=true
assert(ap.canSend() and ap.isActive())
assert(ap.getStatus().lastStopReason~='cooldown')''')

    def test_first_short_cycle_activates_without_artificial_wait(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(80);packet(42,0,100)
packet(99,.1);packet(42,.08)
assert(ap.isActive() and clicks==1,'gate installed an extra wait after observing dangerous return')
assert(ap.getStatus().risk.observedCycle<.19)''')

    def test_slow_previous_exchange_does_not_hide_sudden_short_return(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
other.root.Position=v(80);packet(42,0,100)
packet(99,.3);packet(42,.3);assert(not ap.isActive())
packet(99,.1);packet(42,.12)
assert(ap.isActive() and ap.getStatus().risk.nextCycle<.22)''')

    def test_detector_getter_does_not_send_or_change_ap_timing(self):
        adaptive.AdaptiveParry().check('''
clashing=true;pressure=1;publish(8,600);frame:Fire(1/60)
assert(fires==1)
local d=ap.getPressureDetector()
assert(d.lastAcceptedSample and d.lastAcceptedSample.distance>4)
assert(d.lastAcceptedSample.headroom==nil and d.responseBudget==nil,'AP interpreted danger instead of observing')
local distance=d.lastAcceptedSample.distance
d.lastAcceptedSample.distance=999
for i=1,100 do ap.getPressureDetector() end
assert(fires==1 and ap.getPressureDetector().lastAcceptedSample.distance==distance)
frame:Fire(1/60);assert(fires==1,'same visit created a second AP click')''')

if __name__=='__main__':unittest.main()
