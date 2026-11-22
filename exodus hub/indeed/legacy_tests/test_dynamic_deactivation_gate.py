"""Dynamic owns its cooldown policy and runs without AutoSpam."""
import unittest
from autospam_harness import ENGINE, check
from test_logic_reliability import COMMON, module, run_case

DYNAMIC_SETUP = """
local input={InputBegan=signal(),InputEnded=signal(),WindowFocusReleased=signal(),KeyboardEnabled=true}
function input:GetFocusedTextBox() return nil end
game={GetService=function(_,name) assert(name=='UserInputService');return input end}
Enum.KeyCode={Unknown='unknown'};Enum.UserInputType={Touch='touch',MouseButton1='mouse'}
local dynamicOn=false
u.setDynamicSpamActive=function(value) dynamicOn=value end
u.isDynamicSpamActive=function() return dynamicOn end
g.getDeflectAbility=function() return nil end
r.fireNativeParry=function(guard) assert(guard());return true end
local delayed
task.delay=function(_,fn) delayed=fn end
assert(dynamic.setup({Utils=u,GameInfo=g,Cooldown=c,Remote=r}))
cfg.DynamicParry=true;cfg.DynamicParryKey='key';cfg.DynamicParryMode='Toggle'
local function start()
 input.InputBegan:Fire({KeyCode='key'},false)
 assert(delayed);tm=tm+.18;delayed();input.InputEnded:Fire({KeyCode='key'})
 assert(dynamic.canSend())
end
start()
"""

def dynamic_check(case):
    run_case(COMMON + ENGINE + module('combat/dynamicparry.luau').replace('local mod=', 'local dynamic=', 1) + DYNAMIC_SETUP + case)

class IndependentDeactivationGate(unittest.TestCase):
    def test_runs_without_auto_spam_and_ignores_target_reset_and_distance(self):
        dynamic_check("""
cfg.AutoSpam=false;cfg.AutoSpamClashPrediction=false
snap.targetId=88;snap.teleported=true;snap.resetting=true
snap.ball=instance('BasePart');snap.position=v(300);snap.velocity=v(600)
other.root.Position=v(100);tm=tm+2
assert(dynamic.canSend() and dynamicOn)
""")

    def test_continuous_cooldown_stops_after_initial_protection(self):
        dynamic_check("""
cd.blocking=true;cd.blockingSince=tm
assert(dynamic.canSend());tm=tm+.29;assert(dynamic.canSend())
tm=tm+.02;assert(not dynamic.canSend())
assert(dynamic.getStatus().lastStopReason=='cooldown' and not dynamicOn)
""")

    def test_unknown_reset_and_recovered_cooldowns_do_not_stop(self):
        for state in ("cd.source='unknown'", "cd.predictedReset=true", "cd.blocking=false"):
            with self.subTest(state=state):
                dynamic_check("cd.blocking=true;cd.blockingSince=tm;assert(dynamic.canSend());" + state + ";tm=tm+1;assert(dynamic.canSend())")

    def test_disabled_automatic_deactivation_and_local_death(self):
        dynamic_check("""
cfg.DynamicParryDeactivation=false;cd.blocking=true;cd.blockingSince=tm
tm=tm+2;assert(dynamic.canSend());me.hum.Health=0
assert(not dynamic.canSend() and not dynamicOn)
""")

    def test_auto_spam_survives_ball_reset_but_cooldown_still_stops(self):
        for mutation in ("snap.teleported=true", "snap.resetting=true", "snap.ball=instance('BasePart')"):
            with self.subTest(mutation=mutation):
                check("packet(42,0,2);" + mutation + """
heart:Fire();assert(ap.isActive())
if snap.teleported or snap.resetting then assert(not ap.canSend()) end
cd.blocking=true;cd.blockingSince=tm;advance(.4);heart:Fire()
stopped('cooldown')
""")
