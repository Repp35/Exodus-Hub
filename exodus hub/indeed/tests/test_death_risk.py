"""Exercise real activation and dispatch against deadline and handoff scenarios."""
import unittest
from autospam_harness import check

class DeathRisk(unittest.TestCase):
    def test_incoming_before_first_round_trip(self):
        check('''packet(42,0,40);assert(ap.isActive(),'first dangerous approach missed')
assert(ap.getStatus().risk.source=='incoming');assert(clicks>0)''')

    def test_outbound_predicts_immediate_return(self):
        check('''other.root.Position=v(25);snap.position=v(20);snap.velocity=v(600)
packet(99);assert(ap.isActive(),'outbound return not anticipated')
assert(ap.getStatus().risk.source=='possible_return')''')

    def test_cooldown_never_disables_clash(self):
        check('''packet(42,0,2);local before=clicks
cd.blocking=true;cd.miss=true
for i=1,8 do heartbeat(.05);assert(ap.isActive() and ap.canSend()) end
assert(clicks>before,'cooldown suppressed continuous dispatch')''')

    def test_third_player_handoff_survives_original_partner_death(self):
        check('''packet(42,0,2);other.hum.Health=0;third.root.Position=v(8)
packet(88,.01,4);assert(ap.isActive() and ap.canSend())
assert(ap.getActivationContext().partner==88,'partner not transferred')''')

    def test_approach_and_retreat_use_relative_motion(self):
        for own,other in [(30,-30),(-16,-120),(120,0)]:
            check(f'''me.root.AssemblyLinearVelocity=v({own});other.root.AssemblyLinearVelocity=v({other})
other.root.Position=v(20);packet(42,0,45)
assert(ap.isActive(),'relative-motion danger missed')''')

    def test_uncertain_packet_is_bridged_but_expires(self):
        check('''packet(42,0,2);snap.targetUncertain=true;advance(.05)
assert(ap.canSend(),'single uncertain packet interrupted clash')
advance(.06);assert(not ap.canSend(),'stale target accepted indefinitely')''')

    def test_pause_and_teleport_block_even_during_bridge(self):
        check('''packet(42,0,2);snap.teleported=true;assert(not ap.canSend())
snap.teleported=false;snap.locked=true;assert(not ap.canSend())''')

    def test_distant_ball_does_not_activate(self):
        check('''other.root.Position=v(60);packet(42,0,500)
assert(not ap.isActive(),'distant safe ball triggered spam')''')

    def test_detach_clears_runtime_flag_near_opponent(self):
        check('''packet(42,0,2);ap.detachCharacter();assert(not auto and not ap.canSend())''')

    def test_grace_does_not_restart_when_ball_leaves_radius(self):
        check('''packet(42,0,2);local first=ap.getStatus().risk.deadline
heartbeat(.01);snap.position=v(15);heartbeat(.01)
assert(ap.getStatus().risk.deadline<=first,'grace incorrectly restarted')''')

    def test_curved_direction_does_not_hide_nearby_target(self):
        check('''snap.velocity=v(600);packet(42,0,20)
assert(ap.isActive(),'curved/temporarily outgoing target hid danger')''')

    def test_deadline_grid_across_speed_grace_and_frame_phase(self):
        for speed in (16,100,300,600):
            for grace in (.02,.075,.1):
                for phase in (0,.008,.016):
                    check(f'''g.getDefensePhysics=function() return {{killRadius=4,grace={grace}}} end
snap.speed={speed};snap.syncSpeed={speed};snap.velocity=v(-{speed})
local budget=.05+2/60
snap.position=v(4+{speed}*math.max(0,budget+.04-{grace}-.005))
packet(42,{phase});assert(ap.isActive(),'deadline risk missed in grid')''')

if __name__=='__main__': unittest.main()
