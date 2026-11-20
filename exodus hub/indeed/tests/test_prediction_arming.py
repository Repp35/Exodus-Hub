"""Two-sided danger is armed before the opponent's BlockStart; margin is independent."""
import unittest
from autospam_harness import check
from test_logic_reliability import module

class PredictionArming(unittest.TestCase):
    def test_arms_before_blockstart_and_sends_in_its_event(self):
        check('''
g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,18)
assert(not ap.isActive() and clicks==0)
assert(ap.getStatus().predictionArmed)
assert(ap.getStatus().gates.prediction=='armed_waiting_blockstart')
local before=clicks;animate(99,101)
assert(ap.isActive() and clicks==before+1)
assert(ap.getActivationContext().reason=='extreme_return_prediction')
''')

    def test_only_opponent_blockstart_can_release_armed_prediction(self):
        for phase in (102,103):
            with self.subTest(phase=phase):
                check(f'''g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,18);animate(99,{phase});assert(not ap.isActive())
third.root.Position=v(10);animate(88,101);assert(not ap.isActive())
animate(99,101);assert(ap.isActive())''')

    def test_unrelated_animation_while_ball_targets_self_never_predicts(self):
        check('''g.getDeflectTargetPrediction=function() return 42 end
third.root.Position=v(10);packet(42,0,18);animate(88,101)
assert(not ap.isActive() and not ap.getStatus().predictionArmed)''')

    def test_aim_and_distance_are_revalidated_on_blockstart(self):
        for mutation in ("g.getDeflectTargetPrediction=function() return 88 end", "other.root.Position=v(40)", "snap.position=v(300)", "snap.syncAt=tm-1"):
            with self.subTest(mutation=mutation):
                check('''g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,18);assert(ap.getStatus().predictionArmed)
'''+mutation+";animate(99,101);assert(not ap.isActive() and not ap.getStatus().predictionArmed)")

    def test_old_start_and_old_loop_are_not_new_attempts(self):
        for phase in (101,102):
            with self.subTest(phase=phase):
                check(f'''g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,18);animate(99,{phase},5,1,false);heartbeat(.016)
assert(not ap.isActive())''')

    def test_normal_arrival_and_departing_ball_do_not_arm(self):
        for position,velocity in ((100,-600),(30,600)):
            with self.subTest(position=position):
                check(f'''g.getDeflectTargetPrediction=function() return 42 end
snap.velocity=v({velocity});packet(99,0,{position});animate(99,101)
assert(not ap.isActive() and not ap.getStatus().predictionArmed)''')

    def test_sensitivity_changes_only_return_danger(self):
        for factor,active in ((.5,False),(1,True),(2,True)):
            with self.subTest(factor=factor):
                check(f'''g.getDeflectTargetPrediction=function() return 42 end
cfg.AutoSpamPredictionMargin={factor}
snap.syncSpeed=16;snap.speed=16;snap.velocity=v(-16);other.root.Position=v(13)
packet(99,0,21.5);animate(99,101)
assert(ap.isActive()=={str(active).lower()},tostring(ap.getStatus().gates.prediction))
''')

    def test_default_margin_is_one_and_does_not_change_opponent_radius(self):
        check('''g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,18)
local first=ap.getStatus().predictionEvidence
assert(first.marginFactor==1)
cfg.AutoSpamPredictionMargin=2;heart:Fire()
local second=ap.getStatus().predictionEvidence
assert(second.marginFactor==2 and second.reactionMargin==first.reactionMargin*2)
assert(second.opponentTriggerRadius==first.opponentTriggerRadius)
''')

    def test_reset_and_disabled_prediction_clear_armed_state(self):
        for mutation in ("snap.resetting=true", "cfg.AutoSpamClashPrediction=false", "snap.targetId=88"):
            with self.subTest(mutation=mutation):
                check('''g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,18);assert(ap.getStatus().predictionArmed)
'''+mutation+";heart:Fire();assert(not ap.getStatus().predictionArmed and not ap.isActive())")

    def test_prediction_uses_real_shared_geometry(self):
        check('''
g.getDefenseSource=function() return nil end
g.usesSharedLayout=function() return false end
me.attrs.DeflectRange=8.5;other.attrs.DeflectRange=8.5
assert(realGeometry.setup({GameInfo=g,Utils=u}))
assert(ap.setup({Utils=u,GameInfo=g,Cooldown=c,ClashStats=st,Dash=d,DeflectGeometry=realGeometry}))
assert(ap.bindCharacter(me.Character))
g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,18);assert(ap.getStatus().predictionArmed and not ap.isActive())
animate(99,101);assert(ap.isActive() and clicks>0)
''', extra=module('aux/deflectgeometry.luau').replace('local mod=', 'local realGeometry=', 1))

    def test_ambiguous_aim_does_not_arm_or_fire(self):
        check('''
g.getDeflectTargetPrediction=function() return 42,.9,.001,'camera' end
packet(99,0,18);animate(99,101)
assert(not ap.isActive() and not ap.getStatus().predictionArmed)
assert(ap.getStatus().gates.prediction=='return_aim_uncertain')
''')

    def test_consumed_blockstart_cannot_restart_the_same_leg(self):
        check('''
g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,18);animate(99,101);assert(ap.isActive())
assert(not ap.getStatus().predictionArmed)
ap.stopSpam('stop_spam');animate(99,101);heart:Fire()
assert(not ap.isActive())
''')
