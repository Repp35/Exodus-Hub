import unittest
from autospam_harness import check

class ReturnDeadline(unittest.TestCase):
    def test_ordinary_incoming_ball_does_not_start_spam_even_at_two_studs(self):
        check("cfg.AutoSpamClashPrediction=false;packet(42,0,2);assert(not ap.isActive() and clicks==0)")

    def test_visual_self_vote_cannot_create_the_initial_ownership(self):
        check("cfg.AutoSpamClashPrediction=false;snap.targetUncertain=true;snap.targetId=-1;snap.targetSignals={known=false,signals={{name='ball.targetColor',available=true,targeted=true}}};heartbeat(.01);snap.targetSignals=nil;snap.targetUncertain=false;packet(99,.01,50);packet(42,.1,10);assert(not ap.isActive())")

    def test_real_500ms_return_still_activates_inside_the_window(self):
        check("cfg.AutoSpamClashPrediction=false;packet(42,0,50);packet(99,.01,50);packet(42,.5,10);assert(ap.isActive())")

    def test_close_return_cannot_restart_from_same_receipt(self):
        check("cfg.AutoSpamClashPrediction=false;packet(42,0,50);packet(99,.01,50);packet(42,.1,2);assert(ap.isActive());ap.stopSpam('stop_spam');heart:Fire();assert(not ap.isActive())")

    def test_return_outside_window_cannot_start_on_later_approach(self):
        check("cfg.AutoSpamClashPrediction=false;packet(42,0,50);packet(99,.01,50);packet(42,.1,300);snap.position=v(2);heartbeat(.1);assert(not ap.isActive() and clicks==0)")
