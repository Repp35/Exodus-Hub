"""Behavioral coverage for sustained cooldown Fierce activation, offline."""
from pathlib import Path
import re
import unittest

from test_raw_target_parry import run_lua

SOURCE = (Path(__file__).resolve().parents[2] / 'modules/logic/extras/autofierce.luau').read_text()
SOURCE = re.sub(r'([A-Za-z_][\w.]*) \+= ([^;\n]+?)(?=;|\n| end)', lambda m: f'{m[1]} = {m[1]} + ({m[2]})', SOURCE)
PRELUDE = '''
local tm=10; os.clock=function() return tm end
local heartbeat
local enabled,active,abilities=true,true,true
local player={UserId=42}; local ball={}
local snap={ball=ball,mode='match',syncAt=tm,targetId=42}
local fresh,valid,frozen=true,true,false
local cd={source='local',blocking=true,blockingSince=10,episode=1,miss=false}
local sent,begun,cancelled,manual=0,0,0,0
local ability={Cooldown=0,ActivateAndBlock=function() manual=manual+1 end}
local original=ability.ActivateAndBlock
local approaching,distance=true,10
local window,ping=0.2,0.05
local beforeGuard,failSend
local u={getLocalPlayer=function() return player end,isActive=function() return active end,
 getConfigValue=function() return enabled end,getRunService=function() return {Heartbeat={Connect=function(_,fn) heartbeat=fn; return {Disconnect=function() end} end}} end,
 trackGlobal=function() end,untrackGlobal=function() end}
local g={getDeflectWindow=function() return window end,getAveragePing=function() return ping end,areAbilitiesEnabled=function() return abilities end,getFierceDeflectAbility=function() return ability end,
 getSnapshotAt=function() if fresh then snap.syncAt=tm end; return snap end,
 isSnapshotValid=function() return valid end,getBallFrozen=function() return frozen end}
local a={getTiming=function() return {approaching=approaching,distance=distance,triggerDistance=20} end,beginFierce=function() begun=begun+1; return {} end,cancelFierce=function(token) if token then cancelled=cancelled+1 end end}
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
        run_lua(PRELUDE + '\nlocal mod=(function()\n' + SOURCE + '\nend)()\n' + '''
assert(mod.setup({Utils=u,GameInfo=g,Remote=r,AutoParry=a,Cooldown=c}))
local function step(time) tm=time; heartbeat() end
''' + script)

    def test_waits_for_continuous_threshold_without_miss_or_press_metadata(self):
        self.check('''
step(10); step(10.249); assert(sent==0)
step(10.251); assert(sent==1,'sustained cooldown did not fire')
step(11); assert(sent==1,'same cooldown episode fired twice')
''')

    def test_short_cooldown_and_new_episode_restart_the_timer(self):
        self.check('''
step(10.1); cd.blocking=false; step(10.2); assert(sent==0)
cd.blocking=true; cd.blockingSince=10.2; cd.episode=2
step(10.449); assert(sent==0); step(10.451); assert(sent==1)
cd.blocking=false; step(10.46)
cd.blocking=true; cd.blockingSince=10.5; cd.episode=3
step(10.751); assert(sent==2)
''')

    def test_duration_alone_detects_miss_despite_parry_and_prediction_metadata(self):
        self.check('''
cd.phase='reversible'; cd.missDeadline=11; cd.predictedReset=true
cd.lastParriedAt=10.1; cd.pressAt=nil; cd.miss=false
step(10.249); assert(sent==0)
step(10.251); assert(sent==1,'parry metadata vetoed sustained cooldown')
''')

    def test_window_and_ping_are_captured_when_cooldown_appears(self):
        self.check('''
window=0.85; ping=0.1; step(10)
window=0.2; ping=0
step(10.4); assert(sent==0,'speed change shortened running timer')
step(10.949); assert(sent==0)
step(10.951); assert(sent==1,'slow window plus ping did not expire')
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
        for mutation in ("cd.blocking=false", "cd.episode=2", "snap.targetId=99", "snap.ball={}", "ability.Cooldown=1", "approaching=false", "distance=30", "mod.teardown()"):
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

    def test_manual_activation_and_hook_cleanup_remain(self):
        self.check('''
enabled=false; ability:ActivateAndBlock()
assert(manual==1 and begun==1)
mod.teardown(); assert(ability.ActivateAndBlock==original)
''')

if __name__ == '__main__':
    unittest.main()
