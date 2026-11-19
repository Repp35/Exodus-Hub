"""Replays target observations using the real AutoSpam and Spam scheduler."""
import unittest
from autospam_harness import check

class TargetStreams(unittest.TestCase):
    def test_ap_target_stream_is_not_replaced_by_another_raw_target(self):
        check('''
snap.exchangeTargetId=88;snap.targetSignals={known=true};snap.position=v(20)
local function observed(target)
 snap.targetId=target;snap.targeted=target==42
 ap.onDefenseOpportunity(snap)
end
observed(42);observed(99);observed(42)
assert(ap.isActive() and clicks>0,'AP target transitions were replaced by raw target')
''')

    def test_snapshot_sequence_does_not_discard_later_packet_transitions(self):
        check('''
snap.syncSequence=100;snap.position=v(50);ap.onDefenseOpportunity(snap)
packet(42,0,50,2);packet(99,.01,50,3);packet(42,.01,20,4)
assert(ap.isActive() and clicks>0,'snapshot advanced the packet-only watermark')
''')

    def test_two_observations_from_different_sources_cannot_fabricate_a_round_trip(self):
        check('''
snap.position=v(20);snap.targetSignals={known=true}
local observation=table.clone(snap)
ap.onDefenseOpportunity(observation)
packet(99,0,20)
ap.onDefenseOpportunity(observation)
assert(not ap.isActive(),'unrelated half histories were joined into a round trip')
''')

    def test_packet_and_replicator_share_the_network_target_stream(self):
        check('''
packet(42,0,50);packet(99,.01,50)
snap.targetId=42;snap.targeted=true;snap.syncSequence=snap.syncSequence+1;snap.position=v(20)
ap.onBallSync({Source='replicator',Sequence=snap.syncSequence,TargetPlayerID=42})
assert(ap.isActive() and clicks>0,'replicator completed return was lost')
''')

    def test_animation_works_when_local_player_is_already_target(self):
        check('''
snap.position=v(20);packet(42,0,20);animate(99,101)
assert(ap.isActive() and clicks>0,'animation required enemy-only target')
''')

    def test_return_waits_for_physical_window_without_a_timer_delay(self):
        check('''
packet(42,0,1000);packet(99,.001,1000);packet(42,.001,1000)
assert(not ap.isActive(),'far return skipped TTI window')
snap.position=v(20);heart:Fire(.016)
assert(ap.isActive() and clicks>0,'pending return did not use the next in-window sample')
''')

    def test_proximity_receipt_records_distance_before_local_player_moves(self):
        check('''
packet(42,0,20);me.root.Position=v(18);heart:Fire(.016)
assert(not ap.isActive(),'player movement rewrote distance at target receipt')
''')

    def test_initial_observation_on_another_channel_is_not_a_new_close_receipt(self):
        check('''packet(42,0,50);snap.position=v(2);snap.targetSignals={known=true}
ap.onDefenseOpportunity(snap)
assert(not ap.isActive(),'initial AP sample rewrote the network receipt distance')''')

    def test_opponent_animation_does_not_dispatch_outside_its_window(self):
        check('''
g.getDeflectTargetPrediction=function() return 42 end
packet(99,0,1000);animate(99,101)
assert(not ap.isActive(),'animation bypassed physical TTI window')
snap.position=v(18);heart:Fire(.016)
assert(ap.isActive() and clicks>0,'saved animation was lost before valid TTI')
''')

    def test_direction_scales_window_for_return_and_dispatch(self):
        check('''
packet(42,0,50);packet(99,.001,50);snap.velocity=v(600);packet(42,.001,20)
assert(not ap.isActive(),'receding sample outside raw range authorized a return')
snap.velocity=v(-600);heart:Fire(.016)
assert(ap.isActive() and clicks>0,'incoming TTI within window did not activate')
local before=clicks;snap.position=v(1000)
assert(not ap.canSend(),'active session skipped its physical send window')
''')

    def test_close_receipt_waits_for_real_tti_window_then_dispatches(self):
        check('''snap.realPosition=v(1000);snap.syncDirection=v(-1)
packet(42,0,2);assert(not ap.isActive(),'close appearance bypassed authoritative TTI')
snap.realPosition=v(2);heart:Fire(.016)
assert(ap.isActive() and clicks>0,'saved close receipt was lost before TTI became ready')''')

    def test_return_tracks_leaving_local_and_coming_back_even_if_other_target_changes(self):
        check('''packet(42,0,50);packet(99,.001,50);packet(88,.001,50);packet(42,.001,20)
assert(ap.isActive() and clicks>0,'extra opponent identity condition blocked a fast local return')''')

    def test_optional_prediction_fault_does_not_erase_return_history(self):
        check('''
g.getDeflectTargetPrediction=function() error('camera adapter unavailable') end
packet(42,0,50);packet(99,.001,50);animate(99,101)
assert(ap.getStatus().lastFault,'prediction fault was not diagnosed')
packet(42,.001,20)
assert(ap.isActive() and clicks>0,'prediction failure blocked independent return')
''')
