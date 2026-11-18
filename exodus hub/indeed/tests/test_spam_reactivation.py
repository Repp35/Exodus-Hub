"""Current close-target activation and nonmiss cooldown continuity."""
import unittest
from autospam_harness import check

COUNT = '''
local function stops(reason)
 local n=0;for _,t in ipairs(transitions) do if t[1]=='AutoSpam' and t[3]=='idle' and t[4]==reason then n=n+1 end end
 return n
end
'''

class Reactivation(unittest.TestCase):

    def test_continuous_cooldown_is_a_single_stop_event(self):
        check(COUNT+"""
packet(42,0,2);cd.blocking=true;cd.blockingSince=tm;cd.episode=1
heartbeat(.1);assert(ap.isActive())
heartbeat(.35);stopped('cooldown');assert(stops('cooldown')==1)
packet(99,.01,2);packet(42,.01,2);assert(not ap.isActive(),'blocked cooldown reactivated spam')
cd.blocking=false;heartbeat(.01);packet(99,.01,2);packet(42,.01,2);assert(ap.isActive())
""")


    def test_ball_approaching_without_new_target_receipt_does_not_activate(self):
        check('''
packet(42,0,50);heartbeat(.5);snap.position=v(2);heartbeat(.01)
assert(not ap.isActive(),'later approach created a false target receipt')
''')


    def test_activation_is_idempotent_while_already_active(self):
        check('''
packet(42,0,2);for i=1,100 do heartbeat(.01) end
local count=0;for _,t in ipairs(transitions) do if t[1]=='AutoSpam' and t[3]=='active' then count=count+1 end end
assert(count==1,'active gate republished activation every frame')
''')

if __name__=='__main__': unittest.main()

class VideoRegressions(unittest.TestCase):
    def test_repeated_cooldown_resets_and_miss_flag_preserve_clash(self):
        check('''
packet(42,0,2);cd.miss=true
for i=1,20 do
 cd.blocking=true;cd.blockingSince=tm;cd.episode=i
 heartbeat(.1);assert(ap.isActive(),'short cooldown or miss stopped clash')
 cd.blocking=false;heartbeat(.01);assert(ap.isActive())
end
''')

    def test_physical_departure_overrides_nearby_opponent_and_stale_self_vote(self):
        check('''
packet(42,0,2)
snap.targetId=42;snap.position=v(300);snap.velocity=v(600)
heartbeat(.01);assert(ap.isActive())
heartbeat(.13);stopped('ball_left_exchange');assert(not ap.canSend())
''')

    def test_returning_ball_or_short_outgoing_sample_keeps_session(self):
        check('''
packet(42,0,2);snap.position=v(300);snap.velocity=v(600)
heartbeat(.01);heartbeat(.05);assert(ap.isActive())
snap.velocity=v(-600);heartbeat(.2);assert(ap.isActive(),'returning ball ended clash')
''')

    def test_send_guard_stops_without_waiting_for_heartbeat(self):
        check('''
packet(42,0,2);cd.blocking=true;cd.blockingSince=tm
assert(ap.canSend());advance(.5);ap.canSend();stopped('cooldown')
''')

class DynamicCooldown(unittest.TestCase):
    def test_same_distance_has_different_tolerance_for_fast_and_slow_ball(self):
        for speed in (16,600):
            with self.subTest(speed=speed):
                check(f'''
packet(42,0,2);other.root.Position=v(25)
snap.syncSpeed={speed};snap.speed={speed};snap.velocity=v(-{speed})
cd.blocking=true;cd.blockingSince=tm
heartbeat(.26);assert(ap.isActive()==({speed}==600),'speed did not change cooldown tolerance')
heartbeat(.2);stopped('cooldown')
''')

    def test_moving_beyond_exchange_reaction_time_shortens_running_deadline(self):
        check('''
other.root.Position=v(1);packet(42,0,2)
cd.blocking=true;cd.blockingSince=tm
heartbeat(.26);assert(ap.isActive())
other.root.Position=v(100);ap.canSend();stopped('cooldown')
''')
