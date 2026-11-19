"""Real AutoSpam/Spam/Cooldown: sustained 13-stud clash and prompt far redirects."""
import unittest
from autospam_harness import check
from test_logic_reliability import module

REAL_COOLDOWN = module('aux/cooldown.luau').replace('local mod=', 'local realCooldown=', 1)
BIND_COOLDOWN = '''
local ability={Cooldown=0}
u.getReplicatedStorage=function() return nil end
u.recordError=function() end
g.getDeflectAbility=function() return ability end
assert(realCooldown.setup({Utils=u,GameInfo=g}))
c.getDeflectCooldownState=realCooldown.getDeflectCooldownState
'''
START = '''
other.root.Position=v(13);cfg.CPS=25
packet(42,0,50);packet(99,.04,50);packet(42,.04,50)
assert(ap.isActive(),'fixture did not start auto spam')
local began=tm
'''

class ClashSendContinuity(unittest.TestCase):
    def test_reversible_client_cooldown_cannot_stop_13_stud_clash_at_eight_seconds(self):
        check(BIND_COOLDOWN+START+'''
local beforeCooldown
for i=1,1200 do
 if i==796 then
  beforeCooldown=clicks;ability.Cooldown=.03
  ability.PendingPressAt=tm;ability.PendingPredictUntil=tm+.1
 end
 if i==804 then ability.Cooldown=0;ability.PendingPredictUntil=nil end
 if i%4==0 then packet(snap.targetId==42 and 99 or 42,.01,50) else heartbeat(.01) end
 assert(ap.isActive(),'AutoSpam stopped at '..(tm-began)..'s: '..tostring(ap.getStatus().lastStopReason))
end
assert(clicks>beforeCooldown+90,'dispatch did not continue after transient cooldown')
''',REAL_COOLDOWN)

    def test_manual_and_auto_both_continue_during_identical_reversible_cooldown(self):
        for manual_mode in (False,True):
            with self.subTest(manual=manual_mode):
                check(BIND_COOLDOWN+START+f'''
if {str(manual_mode).lower()} then u.setManualSpamActive(true) end
ability.Cooldown=.03;ability.PendingPressAt=tm;ability.PendingPredictUntil=tm+.1
local before=clicks
for i=1,8 do packet(snap.targetId==42 and 99 or 42,.04,50) end
assert(clicks>before,'mode stopped dispatching under the same ability state')
''',REAL_COOLDOWN)

    def test_short_unknown_target_keeps_sending_without_toggling_active(self):
        check(START+'''
for i=1,6 do packet(snap.targetId==42 and 99 or 42,.04,50) end
snap.targetUncertain=true;heart:Fire();local before=clicks
for i=1,4 do heartbeat(.01);assert(ap.isActive() and ap.canSend()) end
assert(clicks>before,'active flag stayed on but sync uncertainty blocked clicks')
snap.targetUncertain=false;packet(42,.01,50);assert(ap.canSend())
''')

    def test_bridge_expires_without_new_exchange_evidence(self):
        check(START+'''
for i=1,6 do packet(snap.targetId==42 and 99 or 42,.04,50) end
snap.targetUncertain=true;heart:Fire();assert(ap.canSend())
for i=1,30 do heartbeat(.01) end
assert(not ap.canSend(),'uncertainty was allowed to refresh its own evidence')
assert(ap.getStatus().lastSendBlockReason=='target_unknown')
''')

    def test_old_cached_sequence_cannot_interrupt_fresh_clash(self):
        check(START+'''
for i=1,6 do packet(snap.targetId==42 and 99 or 42,.04,50) end
local cached=table.clone(snap)
packet(snap.targetId==42 and 99 or 42,.04,50)
g.getSnapshotAt=function() return cached end
assert(ap.canSend(),'old cache cut current packet flow')
advance(.25);assert(not ap.canSend(),'old cache never expired')
''')

    def test_far_redirect_stops_in_the_same_packet_inside_protection_radius(self):
        for during_cooldown in (False,True):
            with self.subTest(cooldown=during_cooldown):
                check(START+f'''
for i=1,6 do packet(snap.targetId==42 and 99 or 42,.04,50) end
cd.blocking={str(during_cooldown).lower()}
third.root.Position=v(100);local before=clicks
packet(88,0,50)
assert(not ap.isActive() and not ap.canSend(),'far redirect waited for proximity/timer/cooldown')
assert(ap.getStatus().lastStopReason=='target_redirected_far')
heartbeat(.01);assert(clicks==before,'far redirect allowed another automatic click')
''')

    def test_bridge_does_not_override_reset_pause_death_or_disabled(self):
        for mutation in ("snap.teleported=true", "snap.resetting=true", "snap.locked=true",
                         "frozen=true", "me.hum.Health=0", "cfg.AutoSpam=false", "snap.ballValid=false"):
            with self.subTest(mutation=mutation):
                check(START+'''
for i=1,6 do packet(snap.targetId==42 and 99 or 42,.04,50) end
snap.targetUncertain=true
'''+mutation+";assert(not ap.canSend(),'hard stop was bridged')")

    def test_fresh_return_authorizes_dispatch_during_immediate_cache_gap(self):
        check(START+'''
snap.targetUncertain=true;assert(ap.canSend(),'fresh return lost its first dispatch to a cache gap')
advance(.25);assert(not ap.canSend(),'initial evidence refreshed itself without another exchange')
''')

    def test_real_cooldown_mid_dispatch_guard_does_not_cancel_remaining_batch(self):
        check(BIND_COOLDOWN+START+'''
cfg.SpamRateMode='CPF';cfg.CPF=3
local dispatch=r.fireParry
r.fireParry=function(count,guard)
 local sent,detail=dispatch(count,guard)
 if sent then ability.Cooldown=.03;ability.PendingPressAt=tm;ability.PendingPredictUntil=tm+.1 end
 return sent,detail
end
configChanged:Fire({SpamRateMode='CPF',CPF=3})
local before=clicks;heartbeat(.016)
assert(clicks==before+3,'client cooldown cancelled the rest of the same batch')
assert(ap.isActive())
''',REAL_COOLDOWN)

if __name__=='__main__':unittest.main()
