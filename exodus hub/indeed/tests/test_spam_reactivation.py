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

    def test_ordinary_cooldown_is_not_a_stop_event(self):
        check(COUNT+"""
packet(42,0,2);cd.blocking=true;cd.blockingSince=tm;cd.episode=1
heartbeat(2);assert(ap.isActive() and stops('deflect_cooldown_timeout')==0)
""")


    def test_old_close_handoff_is_not_a_lock_when_ball_is_near(self):
        check('''
packet(42,0,50);heartbeat(.5);snap.position=v(2);heartbeat(.01)
assert(ap.isActive(),'old handoff expiry blocked current close danger')
''')


    def test_activation_is_idempotent_while_already_active(self):
        check('''
packet(42,0,2);for i=1,100 do heartbeat(.01) end
local count=0;for _,t in ipairs(transitions) do if t[1]=='AutoSpam' and t[3]=='active' then count=count+1 end end
assert(count==1,'active gate republished activation every frame')
''')

if __name__=='__main__': unittest.main()
