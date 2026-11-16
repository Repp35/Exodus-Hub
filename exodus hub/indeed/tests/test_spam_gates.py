"""Behavioral coverage of the rewritten activation/deactivation state machine."""
import unittest
from autospam_harness import check

class SpamGates(unittest.TestCase):
    def test_fast_returns_at_close_range_dispatch_in_return_packet(self):
        for interval in (.005,.02,.05,.1,.2,.35):
            with self.subTest(interval=interval):
                check(f'''
packet(42,0,50);assert(not ap.isActive())
packet(99,.001);local before=clicks
packet(42,{interval},50)
assert(ap.isActive(),ap.getStatus().lastGate);assert(ap.getActivationContext().reason=='return_target')
assert(clicks==before+1,'no immediate click on activation')
''')

    def test_repeated_identical_positions_do_not_block_clash(self):
        check('''
packet(42,0,50)
for i=1,30 do heartbeat(.02) end
packet(99,.01,50);packet(42,.05,50)
assert(ap.isActive() and clicks>0,'unchanged sampled position blocked target evidence')
''')

    def test_full_radius_plus_maximum_window(self):
        check('''
packet(42,0,200);packet(99,.01);packet(42,.06)
assert(ap.isActive(),'full-radius-only gate blocked the extra window')
for _,factor in ipairs(geometryFactors) do assert(factor==1) end
''')

    def test_single_target_slow_return_far_opponent_and_third_party_do_not_activate(self):
        for case in ("packet(42,0,50);heartbeat(.1)",
                     "packet(42,0,50);packet(99,.01);packet(42,.5)",
                     "other.root.Position=v(50);packet(42,0,50);packet(99,.01);packet(42,.05)",
                     "packet(42,0,50);packet(99,.01);packet(88,.01);packet(42,.05)"):
            with self.subTest(case=case):
                check(case+"\nassert(not ap.isActive() and clicks==0,'unrelated approach started spam')")

    def test_close_ball_eight_studs_and_spawn_already_targeted(self):
        check("packet(42,0,8);assert(ap.isActive() and clicks==1);assert(ap.getActivationContext().reason=='close_target')")
        check("packet(42,0,8.01);assert(not ap.isActive())")
        check("other.root.Position=v(17);packet(42,0,8);assert(not ap.isActive(),'distant bystander triggered close gate')")

    def test_miss_always_stops_both_modes_even_during_reset(self):
        check('''
packet(42,0,8);u.setManualSpamActive(true)
cd.miss=true;snap.teleported=true;heart:Fire()
stopped('deflect_miss');assert(not manual and not ap.canSendManual() and not ap.canSend())
cd.miss=false;snap.teleported=false;packet(99,.01,50);packet(42,.05,50)
assert(ap.isActive(),'stale stopped-partner lock blocked recovery')
''')

    def test_real_cooldown_historical_miss_does_not_latch_new_session(self):
        from test_logic_reliability import module
        extra = module('aux/cooldown.luau').replace('local mod=', 'local realCooldown=', 1)
        # The service models a reversible attempt, a miss, then an expired cooldown.
        setup = """
local ability={Cooldown=0,PendingPressAt=tm,PendingPredictUntil=tm+.2}
g.getDeflectAbility=function() return ability end
u.getReplicatedStorage=function() return nil end
assert(realCooldown.setup({Utils=u,GameInfo=g}))
c.getDeflectCooldownState=realCooldown.getDeflectCooldownState
packet(42,0,8);assert(ap.isActive())
ability.Cooldown=1.45;advance(.21);heartbeat(.01)
stopped('deflect_miss')
ability.Cooldown=0;ability.PendingPredictUntil=nil
local status=realCooldown.getDeflectCooldownState()
assert(status.miss and status.phase=='miss_finished','fixture did not retain historical miss')
packet(99,.01,50);packet(42,.05,50)
assert(ap.isActive() and ap.canSend(),'finished miss latched automatic activation')
u.setManualSpamActive(true);assert(ap.canSendManual(),'finished miss latched manual activation')
"""
        check(setup, extra=extra)

    def test_near_opponent_protects_cooldown_and_return_timeouts(self):
        check('''
packet(42,0,8);cd.blocking=true;cd.blockingSince=tm
packet(99,.01,50);heartbeat(.5);assert(ap.isActive())
''')

    def test_distant_continuous_cooldown_stops_after_180ms_and_resets(self):
        check('''
snap.syncSpeed=16;snap.speed=16;snap.velocity=v(-16)
other.root.Position=v(20);packet(42,0,12);packet(99,.01);packet(42,.05)
assert(ap.isActive());cd.blocking=true;cd.blockingSince=tm
heartbeat(.17);assert(ap.isActive());cd.blocking=false;heartbeat(.01)
cd.blocking=true;cd.blockingSince=tm;heartbeat(.17);assert(ap.isActive())
heartbeat(.02);stopped('deflect_cooldown_timeout')
''')

    def test_distant_nonreturn_stops_after_timeout(self):
        check('''
other.root.Position=v(30);packet(42,0,50);packet(99,.01);packet(42,.05)
assert(ap.isActive());packet(99,.01);heartbeat(.39);assert(ap.isActive());heartbeat(.02)
stopped('target_return_timeout')
''')

    def test_hard_stops(self):
        for action,reason in (("enabled=false",'hub_inactive'),("cfg.AutoSpam=false",'disabled'),
                              ("me.hum.Health=0",'player_died'),("other.hum.Health=0",'opponent_left_or_died'),
                              ("snap.targetId=88",'third_target'),
                              ("snap.ball=instance('BasePart')",'ball_replaced')):
            with self.subTest(reason=reason):
                check("packet(42,0,8);"+action+";ap.canSend();stopped('"+reason+"')")

    def test_distance_uses_its_own_continuous_timer(self):
        check("packet(42,0,8);other.root.Position=v(36);ap.canSend();heartbeat(.249);assert(ap.isActive());heartbeat(.002);ap.canSend();stopped('clash_distance')")

    def test_invalid_samples_pause_without_restarting_or_clicking(self):
        for mutation in ("snap.syncSpeed=-1","snap.syncSpeed=1001","snap.syncSpeed=math.huge","snap.syncSpeed=0/0",
                         "snap.syncSpeed='600'","snap.position=v(0/0)","snap.realPosition=v(math.huge)",
                         "snap.realPosition=v(500)","snap.syncAt=tm-1","snap.targetUncertain=true"):
            with self.subTest(mutation=mutation):
                check(mutation+";heart:Fire();assert(not ap.isActive() and clicks==0)")

    def test_duplicate_old_and_wrapped_sequences(self):
        check('''
packet(42,0,50,65534);packet(99,.01,50,65535)
packet(42,.01,50,65534);assert(not ap.isActive(),'old packet armed a return')
packet(42,.01,50,0);assert(ap.isActive(),'sequence wrap rejected')
local before=clicks;ap.onBallSync({Source='packet',Sequence=0,TargetPlayerID=42,Speed=600});assert(clicks==before)
''')

    def test_disabled_and_detached_never_send(self):
        check("cfg.AutoSpam=false;packet(42,0,8);assert(not ap.isActive() and clicks==0);cfg.AutoSpam=true;packet(42,.01,8);assert(ap.isActive());ap.detachCharacter();assert(not ap.canSend())")

    def test_pause_does_not_consume_return_or_cooldown_timeout(self):
        check("""
other.root.Position=v(30);packet(42,0,50);packet(99,.01);packet(42,.05)
packet(99,.01);cd.blocking=true;cd.blockingSince=tm
snap.locked=true;heartbeat(1);assert(ap.isActive() and not ap.canSend())
snap.locked=false;cd.blocking=false;heartbeat(.01);assert(ap.isActive())
heartbeat(.2);assert(ap.isActive(),'paused time counted toward return')
""")

    def test_reset_does_not_create_fake_return_and_cannot_hide_miss(self):
        check('''
packet(42,0,50);packet(99,.01);snap.teleported=true;heart:Fire()
snap.teleported=false;packet(42,.05,50);assert(not ap.isActive(),'reset combined two rounds')
''')

    def test_fast_packets_between_frames_at_many_distances(self):
        for distance in (2,8,16,34):
            for speed in (16,308,600,1000):
                with self.subTest(distance=distance,speed=speed):
                    check(f"other.root.Position=v({distance});snap.speed={speed};snap.syncSpeed={speed};snap.velocity=v(-{speed});packet(42,0,12);packet(99,.001);packet(42,.02);assert(ap.isActive() and clicks>0)")

    def test_new_ball_sequence_can_restart_at_lower_value(self):
        check("packet(42,0,50,300);snap.ball=instance('BasePart');packet(42,.01,8,1);assert(ap.isActive() and clicks==1)")

    def test_haunter_uses_initial_event_only(self):
        for self_cast in (False,True):
            with self.subTest(self_cast=self_cast):
                check("""
local event={OnClientEvent=signal(),Parent=true}
g.getHaunterEvent=function() return event end
local originalTypeof=typeof;typeof=function(x) if type(x)=='table' and x.cf then return 'CFrame' end return originalTypeof(x) end
packet(42,0,50);heartbeat(.01)
""" + ("event.OnClientEvent:Fire({cf=true,Position=v(0)},{cf=true,Position=v(10)})" if self_cast else "event.OnClientEvent:Fire({cf=true,Position=v(10)},{cf=true,Position=v(5)})") + """
assert(ap.isActive(),'initial haunter evidence did not activate')
heartbeat(.5);assert(ap.isActive(),'haunter initial window stayed active as a stop gate')
""")

    def test_diagnostics_expose_all_failed_candidates(self):
        check('''
packet(42,0,50);local status=ap.getStatus()
assert(status.gates.dash and status.gates.returnTarget and status.gates.close and status.gates.haunter)
assert(status.gates.returnTarget=='return_no_round_trip')
''')

if __name__=='__main__': unittest.main()
