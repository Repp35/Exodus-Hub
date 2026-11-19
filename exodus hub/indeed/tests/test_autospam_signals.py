"""Observable animation recovery and activation; no required gates or tuning constants."""
import unittest
from autospam_harness import check

class AnimationRecovery(unittest.TestCase):
    def test_animation_and_target_in_either_order(self):
        for before in (True,False):
            with self.subTest(before=before):
                check('''
g.getDeflectTargetPrediction=function() return 42 end
other.root.Position=v(10)
'''+("animate(99,101);packet(99,0,18)" if before else "packet(99,0,18);animate(99,101)")+'''
assert(ap.isActive() and clicks>0,'animation/target ordering lost activation')
packet(42,.02,5);assert(ap.isActive() and ap.canSend(),'return confirmation lost session')
''')

    def test_missed_event_is_recovered_from_playing_tracks(self):
        check('''
g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,18);animate(99,101,0,1,false);heartbeat(.016)
assert(ap.isActive() and clicks>0,'playing-track recovery failed')
''')

    def test_streamed_animation_id_is_discovered(self):
        check('''
g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,18);animationCatalog['777']='start';animate(99,777)
assert(ap.isActive() and clicks>0,'new animation asset was missed')
''')

    def test_start_loop_and_success_are_recognized(self):
        for phase in (101,102,103):
            with self.subTest(phase=phase):
                check(f'''g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,18);animate(99,{phase});assert(ap.isActive() and clicks>0)''')

    def test_outbound_prediction_prepares_then_dispatches_on_opponent_animation(self):
        check('''g.getDeflectTargetPrediction=function() return 42 end
packet(42,0,50);packet(99,.001,18)
assert(not ap.isActive() and clicks==0,'outbound contact fired animation prediction without an animation')
local prepared=ap.getStatus().predictionArmed
assert(prepared and prepared.ready,'prediction was not prepared before animation')
animate(99,101)
assert(ap.isActive() and clicks>0,'opponent animation did not release prepared prediction')''')

    def test_detach_releases_all_observers(self):
        check('''
packet(42,0,2);ap.detachCharacter()
assert(not ap.canSend() and next(tracked)==nil,'detached character retained observers')
assert(ap.bindCharacter(me.Character));packet(42,.03,2)
assert(ap.isActive(),'rebind did not recover')
''')

    def test_animation_during_temporary_uncertainty_survives_until_packet(self):
        check('''
g.getDeflectTargetPrediction=function() return 42 end
snap.targetUncertain=true;animate(99,101)
snap.targetUncertain=false;packet(99,.016,18)
assert(ap.isActive() and clicks>0,'temporary uncertainty erased animation')
''')
