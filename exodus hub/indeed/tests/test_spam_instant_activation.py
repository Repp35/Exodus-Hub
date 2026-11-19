"""Observed activation outcomes: independent proximity, animation, return and AP handoff.

These cases require successful activation and dispatch, not particular gate names,
implementation structure, or additional rejection rules.
"""
import unittest
from autospam_harness import check
from test_logic_reliability import module

class InstantActivation(unittest.TestCase):
    def test_later_approach_does_not_replace_distance_when_target_was_received(self):
        check('''packet(42,0,50);snap.position=v(2);heartbeat(.016)
assert(not ap.isActive() and clicks==0,'later approach incorrectly created a proximity activation')''')

    def test_moving_player_closer_does_not_rewrite_target_receipt(self):
        check('''packet(42,0,20);me.root.Position=v(18);heartbeat(.016)
assert(not ap.isActive(),'movement rewrote distance at the moment of targeting')''')

    def test_proximity_does_not_wait_for_identifying_the_partner(self):
        check('''other.root.Position=v(80);third.root.Position=v(100)
packet(42,0,2);assert(ap.isActive() and clicks>0)''')

    def test_proximity_survives_old_sync_position_and_zero_render_velocity(self):
        check('''snap.realPosition=v(500);snap.velocity=v();packet(42,0,2)
assert(ap.isActive() and clicks>0)''')

    def test_fast_round_trip_alone_dispatches_on_return(self):
        for speed in (16,83,600):
            for interval in (.001,.01,.05,.2):
                with self.subTest(speed=speed,interval=interval):
                    check(f'''snap.syncSpeed={speed};snap.speed={speed};snap.velocity=v({speed})
packet(42,0,500);packet(99,.001,500);packet(42,{interval},500)
assert(ap.isActive() and clicks>0,'return was vetoed by render trajectory')''')

    def test_target_attribute_events_capture_two_switches_between_packets(self):
        check('''snap.targetSignals={known=false};snap.targetUncertain=true;snap.targetId=-1
snap.exchangeTargetId=99
for _,target in ipairs({42,99,42}) do
 ap.onBallSync({Source='target',TargetPlayerID=target})
end
assert(ap.isActive() and clicks>0,'same-sequence attribute transitions disappeared')''')

    def test_fresh_return_can_reactivate_between_frames(self):
        check('''packet(42,0,2);ap.stopSpam('stop_spam')
packet(99,.001,500);packet(42,.001,500)
assert(ap.isActive() and ap.canSend(),'fresh return waited for a rearm timer')''')

    def test_animation_anticipates_despite_outgoing_render_velocity(self):
        check('''g.getDeflectTargetPrediction=function() return 42 end
snap.velocity=v(600);packet(99,0,18);animate(99,101)
assert(ap.isActive() and clicks>0,'outgoing render velocity vetoed defense animation')''')

    def test_animation_before_target_event_survives_snapshot_conflict(self):
        check('''g.getDeflectTargetPrediction=function() return 42 end
snap.targetUncertain=true;snap.position=v(18);animate(99,101)
ap.onBallSync({Source='target',TargetPlayerID=99})
assert(ap.isActive() and clicks>0,'target conflict blocked observed opponent defense')''')

    def test_same_frame_defense_opportunity_dispatches_without_heartbeat(self):
        check('''snap.position=v(2);snap.targetSignals={known=true}
ap.onDefenseOpportunity(snap)
assert(ap.isActive() and clicks>0,'AP opportunity did not reach auto spam')''')

    def test_real_ap_gives_spam_the_opportunity_before_single_deflect(self):
        check('''
g.isTrainingArea=function() return false end
g.observeTraining=function(fn) return signal():Connect(fn) end
g.getRootPosition=function(root) return root.Position end
g.getDeflectAbility=function() return nil end
g.getSyncSequence=function() return snap.syncSequence end
g.getSyncData=function() return {} end
g.getParryTargetStatus=function() return {known=true,targeted=true,targetId=42} end
u.isSpamActive=function() return auto or manual end
local singleClicks=0
local singleRemote={fireParry=function(_,guard) if guard() then singleClicks=singleClicks+1;return true end return false end}
assert(realAP.setup({Utils=u,GameInfo=g,Remote=singleRemote,Cooldown=c,AutoSpam=ap}))
assert(realAP.bindCharacter(me.Character))
snap.position=v(2);snap.targetSignals={known=true}
realAP.onBallSync({Source='target'})
assert(ap.isActive() and clicks>0,'AP ran without activating eligible spam')
assert(singleClicks==0,'single AP click consumed the spam opportunity')
''',module('autoparry.luau').replace('local mod=', 'local realAP=',1))
