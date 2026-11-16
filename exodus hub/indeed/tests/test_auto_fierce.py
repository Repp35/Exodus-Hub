"""Behavioral coverage for sustained cooldown Fierce activation, offline."""
import unittest

from test_logic_reliability import module, run_case

SOURCE = module('extras/autofierce.luau')
PRELUDE = '''
local tm=10; os.clock=function() return tm end
local heartbeat
local enabled,active,abilities=true,true,true
local player={UserId=42}; local ball={}
local snap={ball=ball,mode='match',syncAt=tm,targetId=42}
local fresh,valid,frozen=true,true,false
local cd={source='local',blocking=true,blockingSince=10,episode=1,miss=false}
local sent,begun,cancelled,manual=0,0,0,0
local stoppedAuto,stoppedAll=0,0
local ability={Cooldown=0,ActivateAndBlock=function() manual=manual+1 end}
local original=ability.ActivateAndBlock
local approaching,distance=true,10
local killTime,entry,rawRadius
local window,ping=0.2,0.05
local inClash=false
local beforeGuard,failSend
local u={getLocalPlayer=function() return player end,isActive=function() return active end,
 getConfigValue=function() return enabled end,getRunService=function() return {Heartbeat={Connect=function(_,fn) heartbeat=fn; return {Disconnect=function() end} end}} end,
 trackGlobal=function() end,untrackGlobal=function() end,
 stopAllSpam=function() stoppedAll=stoppedAll+1 end}
local spam={stopSpam=function() stoppedAuto=stoppedAuto+1 end}
local g={getDefensePhysics=function() return {inClash=inClash} end,getDeflectWindow=function() return window end,getAveragePing=function() return ping end,areAbilitiesEnabled=function() return abilities end,getFierceDeflectAbility=function() return ability end,
 getSnapshotAt=function() if fresh then snap.syncAt=tm end; return snap end,
 isSnapshotValid=function() return valid end,getBallFrozen=function() return frozen end}
local a={getTiming=function() return {approaching=approaching,distance=distance,triggerDistance=20,timeToKill=killTime,predictionTimeToRange=entry,noWindowParryRadius=rawRadius} end,beginFierce=function() begun=begun+1; return {} end,cancelFierce=function(token) if token then cancelled=cancelled+1 end end}
local c={getDeflectCooldownState=function() return cd end}
local r={fireFierce=function(guard)
 if beforeGuard then beforeGuard() end
 if not guard() then return false end
 if failSend then return false end
 sent=sent+1; return true
end}
'''

class AutoFierceTests(unittest.TestCase):
    def check(self, script):
        run_case(PRELUDE + SOURCE + '''
assert(mod.setup({Utils=u,GameInfo=g,Remote=r,AutoParry=a,Cooldown=c,AutoSpam=spam}))
local function step(time) tm=time; heartbeat() end
''' + script)

    def test_waits_for_continuous_threshold_without_miss_or_press_metadata(self):
        self.check('''
step(10); step(10.316); assert(sent==0)
step(10.318); assert(sent==1,'sustained cooldown did not fire')
step(11); assert(sent==1,'same cooldown episode fired twice')
''')

    def test_short_cooldown_and_new_episode_restart_the_timer(self):
        self.check('''
step(10.1); cd.blocking=false; step(10.2); assert(sent==0)
cd.blocking=true; cd.blockingSince=10.2; cd.episode=2
step(10.516); assert(sent==0); step(10.518); assert(sent==1)
cd.blocking=false; step(10.52)
cd.blocking=true; cd.blockingSince=10.6; cd.episode=3
step(10.918); assert(sent==2)
''')

    def test_scheduled_parry_extends_deadline_and_waits_for_server_response(self):
        self.check('''
cd.missDeadline=10.8; step(10)
step(10.5); assert(sent==0,'Fierce spent while scheduled parry could still resolve')
cd.missDeadline=nil
step(10.9); assert(sent==0,'lost pending deadline after client cleared it')
step(10.918); assert(sent==1,'did not fire after pending parry and response margin')
''')

    def test_later_scheduled_parry_extends_existing_timer(self):
        self.check('''
cd.missDeadline=10.4; step(10)
cd.missDeadline=10.9; step(10.3)
cd.missDeadline=nil; step(10.8); assert(sent==0)
step(11.018); assert(sent==1)
''')

    def test_predicted_reset_blocks_until_confirmation_period_ends(self):
        self.check('''
cd.predictedReset=true; step(10.5); assert(sent==0)
cd.predictedReset=false; step(10.6); assert(sent==1)
''')

    def test_parry_reset_during_pending_period_prevents_fierce(self):
        self.check('''
cd.missDeadline=10.8; step(10)
cd.blocking=false; cd.lastParriedAt=10.75; step(10.75)
cd.missDeadline=nil; step(11); assert(sent==0)
''')

    def test_clash_suppression_ends_with_clash_in_the_same_episode(self):
        self.check('''
inClash=true; step(10); step(10.6); assert(sent==0,'Fierce spent in clash')
inClash=false; step(10.7); assert(sent==1,'clash permanently vetoed rescue after exit')
cd.blocking=false; step(10.8)
cd.blocking=true; cd.blockingSince=11; cd.episode=2
step(11); step(11.318); assert(sent==2,'fresh cooldown outside clash was blocked')
''')

    def test_teardown_clears_clash_episode_for_reexecution(self):
        self.check('''
inClash=true; step(10); mod.teardown()
inClash=false
assert(mod.setup({Utils=u,GameInfo=g,Remote=r,AutoParry=a,Cooldown=c,AutoSpam=spam}))
step(10.5); assert(sent==1,'reexecution retained discarded clash episode')
''')

    def test_duration_does_not_require_click_or_miss_metadata(self):
        self.check('''
cd.lastParriedAt=10.1; cd.pressAt=nil; cd.miss=false
step(10.316); assert(sent==0)
step(10.318); assert(sent==1)
''')

    def test_window_and_ping_are_captured_when_cooldown_appears(self):
        self.check('''
window=0.85; ping=0.1; step(10)
window=0.2; ping=0
step(10.4); assert(sent==0,'speed change shortened running timer')
step(11.066); assert(sent==0)
step(11.068); assert(sent==1,'slow window plus ping did not expire')
''')

    def test_invalid_window_or_ping_does_not_activate(self):
        for invalid in ("window=nil", "window=0/0", "window=0", "ping=nil", "ping=0/0", "ping=-1"):
            with self.subTest(invalid=invalid):
                self.check(invalid + '; step(11); assert(sent==0)')

    def test_incoming_ball_must_be_in_range(self):
        self.check('''
approaching=false; step(10.2); assert(sent==0)
approaching=true; distance=30; step(10.3); assert(sent==0)
distance=10; step(10.4); assert(sent==1)
''')

    def test_unknown_cooldown_or_duration_does_not_activate(self):
        for invalid in ("cd.source='unknown'", "cd.blocking=false", "cd.blocking=nil", "cd.blockingSince=nil", "cd.blockingSince=11", "cd.blockingSince=0/0", "cd.episode=nil"):
            with self.subTest(invalid=invalid):
                self.check(invalid + '; step(10.5); assert(sent==0)')

    def test_wrong_target_stale_snapshot_and_unavailable_ability_do_not_activate(self):
        for invalid in ("snap.targetId=99", "snap.targetUncertain=true", "snap.teleported=true", "snap.locked=true", "frozen=true", "valid=false", "fresh=false", "ability.Cooldown=1", "ability.Cooldown=nil", "ability.Cooldown=0/0", "enabled=false", "active=false", "abilities=false"):
            with self.subTest(invalid=invalid):
                self.check(invalid + '; step(10.5); assert(sent==0)')

    def test_checks_again_immediately_before_send(self):
        for mutation in ("cd.blocking=false", "cd.episode=2", "cd.missDeadline=tm+0.5", "cd.predictedReset=true", "inClash=true", "snap.targetId=99", "snap.ball={}", "ability.Cooldown=1", "approaching=false", "distance=30", "mod.teardown()"):
            with self.subTest(mutation=mutation):
                self.check('beforeGuard=function() ' + mutation + ' end; step(10.5); assert(sent==0)')

    def test_reentrant_update_does_not_send_twice(self):
        self.check('''
beforeGuard=function() heartbeat() end
step(10.5); assert(sent==1)
''')

    def test_failed_send_cancels_ap_lock_and_can_retry(self):
        self.check('''
failSend=true; step(10.5); assert(sent==0 and cancelled==1)
failSend=false; step(10.6); assert(sent==1)
''')

    def test_real_cooldown_pending_deadline_survives_client_expiry(self):
        run_case(PRELUDE + '''
local deflect={Cooldown=1.45,PendingPressAt=10,PendingPredictUntil=10.8}
g.getDeflectAbility=function() return deflect end
u.getReplicatedStorage=function() return nil end
u.recordError=function(_,message) error(message) end
''' + module('aux/cooldown.luau') + '''
local realCooldown=mod
assert(realCooldown.setup({Utils=u,GameInfo=g}))
''' + SOURCE + '''
assert(mod.setup({Utils=u,GameInfo=g,Remote=r,AutoParry=a,Cooldown=realCooldown,AutoSpam=spam}))
heartbeat(); tm=10.5; heartbeat(); assert(sent==0)
deflect.PendingPredictUntil=nil; deflect.Cooldown=0.65
tm=10.8; heartbeat(); assert(sent==1,'confirmed miss waited through another response margin')
tm=10.918; heartbeat(); assert(sent==1,'same miss consumed Fierce twice')
mod.teardown(); realCooldown.teardown()
''')

    def test_manual_activation_and_hook_cleanup_remain(self):
        self.check('''
enabled=false; ability:ActivateAndBlock()
assert(manual==1 and begun==1)
mod.teardown(); assert(ability.ActivateAndBlock==original)
''')

    def test_confirmed_miss_rescues_inside_lingering_clash_and_stops_spam(self):
        self.check('''
inClash=true; cd.miss=true; cd.windowExpired=true; cd.windowEndsAt=10.03
step(10); assert(sent==0)
step(10.031); assert(sent==1,'clash vetoed confirmed miss rescue')
assert(stoppedAuto==1 and stoppedAll==1 and begun==1,'rescue did not take priority over spam')
step(10.1); assert(sent==1)
''')

    def test_imminent_death_rescues_before_normal_threshold(self):
        self.check('''
inClash=true; killTime=.04; entry=.03
cd.windowEndsAt=10.01; cd.windowExpired=true
step(10.02); assert(sent==1,'emergency waited for normal sustained timer')
''')

    def test_pending_parry_and_recovery_before_danger_preserve_fierce(self):
        self.check('''
inClash=true; killTime=.08; entry=.02
cd.windowEndsAt=10.1; cd.windowExpired=false
step(10.01); assert(sent==0,'usable pending window was ignored')
cd.windowEndsAt=10.005; cd.windowExpired=true; cd.miss=true
cd.remaining=.001; killTime=.3
step(10.02); assert(sent==0,'Fierce spent despite cooldown recovering before danger')
''')

    def test_stationary_ball_inside_raw_range_still_allows_rescue(self):
        self.check('''
approaching=false; distance=6; rawRadius=8.5; frozen=nil
cd.miss=true; cd.windowExpired=true; inClash=true
step(10.1); assert(sent==1)
''')

    def test_unavailable_or_dead_owner_cannot_spend_fierce(self):
        for method in ('IsOwnerAlive', 'IsAvailable'):
            with self.subTest(method=method):
                self.check('ability.' + method + '=function() return false end; step(11); assert(sent==0)')

    def test_automatic_activation_uses_one_ap_lock(self):
        self.check('''
r.fireFierce=function(guard)
 if not guard() then return false end
 assert(stoppedAuto==1 and stoppedAll==1,'spam still active at Fierce dispatch')
 ability:ActivateAndBlock(); sent=sent+1; return true
end
step(10.5); assert(sent==1 and manual==1 and begun==1,'automatic wrapper duplicated AP lock')
''')

if __name__ == '__main__':
    unittest.main()
