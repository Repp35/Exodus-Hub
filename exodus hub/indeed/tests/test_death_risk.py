"""Physics observations support a future-exchange gate, never a second sender."""
import unittest
from autospam_harness import check

class DeathRisk(unittest.TestCase):
    def test_ball_distance_changes_estimated_deadline_without_forcing_activation(self):
        check('''other.root.Position=v(100);packet(99,0,500);packet(42,.01,100)
local first=ap.getStatus().risk.deadline
packet(42,.01,20)
assert(ap.getStatus().risk.deadline<first)
assert(not ap.isActive(),'deadline observation became a separate click path')''')

    def test_grace_observation_is_not_restarted_by_leaving_radius(self):
        check('''other.root.Position=v(100);packet(99,0,500);packet(42,.01,4)
local first=ap.getStatus().risk.deadline
heartbeat(.01);snap.position=v(15);heartbeat(.01)
assert(ap.getStatus().risk.deadline<=first)''')

    def test_approach_projects_shorter_next_cycle_than_retreat(self):
        check('''other.root.Position=v(60);snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300)
packet(99,0,500);packet(42,.01,100)
local base=ap.getStatus().risk.predictedCycle
other.root.AssemblyLinearVelocity=v(-120);heartbeat(.01)
assert(ap.getStatus().risk.predictedCycle<base,'relative approach was ignored')''')

    def test_missing_opponents_does_not_create_a_clash_partner(self):
        check('''other.hum.Health=0;third.hum.Health=0;packet(42,0,20)
assert(not ap.isActive() and ap.getStatus().risk.partner==nil)''')

    def test_old_samples_do_not_change_new_ball_risk(self):
        check('''snap.speed=300;snap.syncSpeed=300;snap.velocity=v(-300);other.root.Position=v(50)
packet(99,0,500)
defense.lastAcceptedSample={at=tm-1,ball=ball,distance=4,speed=300}
packet(42,.01,100);assert(not ap.isActive())''')

    def test_sender_remains_blocked_on_reset_and_pause(self):
        check('''packet(42,0,2);snap.teleported=true;assert(not ap.canSend())
snap.teleported=false;snap.locked=true;assert(not ap.canSend())''')

if __name__=='__main__':unittest.main()
