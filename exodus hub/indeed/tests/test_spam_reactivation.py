"""A stop occurrence fires once; live activation remains independent after 20 ms."""
import unittest
from autospam_harness import check

COUNT = '''
local function stops(reason)
 local n=0;for _,t in ipairs(transitions) do if t[1]=='AutoSpam' and t[3]=='idle' and t[4]==reason then n=n+1 end end
 return n
end
'''

class Reactivation(unittest.TestCase):
    def test_miss_blocks_reactivation_until_finished(self):
        check(COUNT+"""
packet(42,0,2);u.setManualSpamActive(true);cd.miss=true;cd.blocking=true;cd.episode=1
heartbeat(.01);stopped('deflect_miss');local before=clicks
for i=1,30 do heartbeat(.01);assert(not ap.isActive() and not ap.canSend() and not manual) end
assert(clicks==before and stops('deflect_miss')==1)
u.setManualSpamActive(true);assert(not ap.canSendManual() and not manual)
cd.blocking=false;cd.phase='miss_finished';heartbeat(.01)
assert(ap.isActive() and clicks>before,'finished miss prevented recovery')
""")

    def test_ordinary_cooldown_is_not_a_stop_event(self):
        check(COUNT+"""
packet(42,0,2);cd.blocking=true;cd.blockingSince=tm;cd.episode=1
heartbeat(2);assert(ap.isActive() and stops('deflect_cooldown_timeout')==0)
""")

    def test_miss_wait_is_independent_of_normal_timeout(self):
        check(COUNT+"""
packet(42,0,2);cd.miss=true;cd.blocking=true;cd.episode=1
heartbeat(.01);heartbeat(.25);assert(not ap.isActive())
cd.miss=false;cd.blocking=false;heartbeat(.01);assert(ap.isActive())
""")

    def test_old_close_handoff_is_not_a_lock_when_ball_is_near(self):
        check('''
packet(42,0,50);heartbeat(.5);snap.position=v(2);heartbeat(.01)
assert(ap.isActive(),'old handoff expiry blocked current close danger')
ap.stopSpam('fierce_rescue');heartbeat(.021);assert(ap.isActive(),'fierce stop consumed close evidence')
''')

    def test_same_return_can_rearm_while_still_valid(self):
        check('''
packet(42,0,50);packet(99,.01);packet(42,.05);assert(ap.isActive())
ap.stopSpam('stop_spam');heartbeat(.021);assert(ap.isActive(),'stop erased still-valid return')
''')

    def test_same_haunter_can_rearm_while_still_valid(self):
        check("""
local event={OnClientEvent=signal(),Parent=true};g.getHaunterEvent=function() return event end
local oldTypeof=typeof;typeof=function(x) if type(x)=='table' and x.cf then return 'CFrame' end return oldTypeof(x) end
packet(42,0,50);heartbeat(.01)
event.OnClientEvent:Fire({cf=true,Position=v(10)},{cf=true,Position=v(5)})
assert(ap.isActive());ap.stopSpam('stop_spam');heartbeat(.021)
assert(ap.isActive() and ap.getActivationContext().reason=='haunter','stop consumed valid haunter')
""")

    def test_repeated_clicks_do_not_turn_one_cooldown_into_multiple_misses(self):
        check(COUNT+"""
packet(42,0,2);cd.miss=true;cd.blockingSince=tm;cd.pressAt=tm
heartbeat(.01);stopped('deflect_miss');heartbeat(.021);assert(not ap.isActive())
for i=1,10 do cd.pressAt=tm;heartbeat(.01);assert(not ap.isActive()) end
assert(stops('deflect_miss')==1)
cd.miss=false;heartbeat(.01);cd.miss=true;heartbeat(.01);stopped('deflect_miss')
assert(stops('deflect_miss')==2,'fresh miss was hidden by prior occurrence')
""")

    def test_stop_when_idle_does_not_extend_deadline_or_repeat_transition(self):
        check(COUNT+'''
packet(42,0,2);ap.stopSpam('stop_spam');local stopAt=ap.getStatus().lastStopAt
for i=1,10 do advance(.001);ap.stopSpam('stop_spam') end
assert(stops('stop_spam')==1 and ap.getStatus().lastStopAt==stopAt)
heartbeat(.011);assert(ap.isActive(),'repeated idle stop extended cooldown')
''')

    def test_activation_is_idempotent_while_already_active(self):
        check('''
packet(42,0,2);for i=1,100 do heartbeat(.01) end
local count=0;for _,t in ipairs(transitions) do if t[1]=='AutoSpam' and t[3]=='active' then count=count+1 end end
assert(count==1,'active gate republished activation every frame')
''')

if __name__=='__main__': unittest.main()
