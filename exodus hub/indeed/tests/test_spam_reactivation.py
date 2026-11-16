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
    def test_miss_is_one_event_not_a_continuous_activation_veto(self):
        check(COUNT+'''
packet(42,0,5);u.setManualSpamActive(true);cd.miss=true;cd.episode=1
heartbeat(.01);stopped('deflect_miss');assert(not manual and stops('deflect_miss')==1)
local stopAt=ap.getStatus().lastStopAt
for i=1,10 do ap.canSend();ap.stopSpam('deflect_miss') end
heartbeat(.019);assert(not ap.isActive());assert(ap.getStatus().lastStopAt==stopAt)
heartbeat(.002);assert(ap.isActive(),'held miss blocked reactivation after 20 ms')
u.setManualSpamActive(true);assert(manual and ap.canSendManual(),'same miss repeatedly disabled manual')
for i=1,10 do heartbeat(.01);assert(ap.isActive() and manual) end
assert(stops('deflect_miss')==1)
cd.episode=2;heartbeat(.01);stopped('deflect_miss');assert(not manual and stops('deflect_miss')==2)
''')

    def test_cooldown_timeout_fires_once_without_waiting_for_cooldown_to_clear(self):
        check(COUNT+'''
snap.speed=16;snap.syncSpeed=16;snap.velocity=v(-16);other.root.Position=v(20)
packet(42,0,12);packet(99,.01);packet(42,.05)
cd.blocking=true;cd.blockingSince=tm;cd.episode=1
heartbeat(.181);stopped('deflect_cooldown_timeout')
heartbeat(.021);assert(ap.isActive(),'same cooldown latched return gate')
for i=1,10 do heartbeat(.01);assert(ap.isActive()) end
assert(stops('deflect_cooldown_timeout')==1)
cd.episode=2;cd.blockingSince=tm;heartbeat(.181);stopped('deflect_cooldown_timeout')
assert(stops('deflect_cooldown_timeout')==2)
''')

    def test_independent_miss_and_timeout_events(self):
        check(COUNT+'''
snap.speed=16;snap.syncSpeed=16;snap.velocity=v(-16);other.root.Position=v(20)
packet(42,0,12);packet(99,.01);packet(42,.05)
cd.blocking=true;cd.blockingSince=tm;cd.miss=true;cd.episode=1
heartbeat(.01);stopped('deflect_miss');heartbeat(.021);assert(ap.isActive())
heartbeat(.16);stopped('deflect_cooldown_timeout')
assert(stops('deflect_miss')==1 and stops('deflect_cooldown_timeout')==1)
heartbeat(.021);assert(ap.isActive(),'one reason suppressed independent activation')
''')

    def test_old_close_handoff_is_not_a_lock_when_ball_is_near(self):
        check('''
packet(42,0,50);heartbeat(.5);snap.position=v(5);heartbeat(.01)
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
packet(42,0,5);cd.miss=true;cd.blockingSince=tm;cd.pressAt=tm
heartbeat(.01);stopped('deflect_miss');heartbeat(.021);assert(ap.isActive())
for i=1,10 do cd.pressAt=tm;heartbeat(.01);assert(ap.isActive()) end
assert(stops('deflect_miss')==1)
cd.miss=false;heartbeat(.01);cd.miss=true;heartbeat(.01);stopped('deflect_miss')
assert(stops('deflect_miss')==2,'fresh miss was hidden by prior occurrence')
""")

    def test_stop_when_idle_does_not_extend_deadline_or_repeat_transition(self):
        check(COUNT+'''
packet(42,0,5);ap.stopSpam('stop_spam');local stopAt=ap.getStatus().lastStopAt
for i=1,10 do advance(.001);ap.stopSpam('stop_spam') end
assert(stops('stop_spam')==1 and ap.getStatus().lastStopAt==stopAt)
heartbeat(.011);assert(ap.isActive(),'repeated idle stop extended cooldown')
''')

    def test_activation_is_idempotent_while_already_active(self):
        check('''
packet(42,0,5);for i=1,100 do heartbeat(.01) end
local count=0;for _,t in ipairs(transitions) do if t[1]=='AutoSpam' and t[3]=='active' then count=count+1 end end
assert(count==1,'active gate republished activation every frame')
''')

if __name__=='__main__': unittest.main()
