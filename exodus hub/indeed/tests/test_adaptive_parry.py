"""Parry timing regressions grounded in the supplied Olymp4 client dump.

DeflectAbility.estimateWindow: .85 -> .20 seconds, then clash pressure.
GameBall.GetKillDistance: 4; base parry range: 8.5.
The engine simulator is doubled; production GameInfo/AP code runs unchanged.
"""
import unittest

from test_logic_reliability import COMMON, GAME_INFO, module, run_case


SETUP = '''
local oldIndex=V.__index
V.__index=function(t,k) if k=='Unit' then return t/t.Magnitude end return oldIndex(t,k) end
function V:Dot(other) return self.X*other.X+self.Y*other.Y+self.Z*other.Z end
local pressure,clashing,ping,baseFactor=0,false,0,.4
local frame=signal();character.AncestryChanged=signal()
player.GetNetworkPing=function() return ping end
player.GetAttribute=function(_,key) if key=='DeflectRange' then return 8.5 end return 1 end
local players={LocalPlayer=player,GetPlayerByUserId=function(_,id) if id==42 then return player end end}
u.getPlayers=function() return players end
u.getLocalPlayer=function() return player end
u.getRunService=function() return {PostSimulation=frame} end
u.isActive=function() return true end
u.isSpamActive=function() return false end
u.getConfigValue=function(key) if key=='AutoParryWindowFactor' then return baseFactor end return true end
u.apiVersion=function() return 1 end
for _,key in ipairs({'trackCharacter','untrackCharacter','recordTransition','recordError'}) do u[key]=function() end end
root.AssemblyLinearVelocity=v()
world.GetServerTimeNow=function() return tm end
local gameBallModule=instance('ModuleScript')
shared.children.Gameplay.children.GameBall=gameBallModule
local gameBall={GetBaseSpeed=function() return 16 end,GetMaxSpeed=function() return 600 end,
 IsInClash=function() return clashing end,GetKillDistance=function() return 4 end,
 GetClashMinWindow=function(_,speed) return .22+.1*math.clamp((speed-16)/250,0,1) end,
 ApplyClashPressure=function(_,window) return window+(math.min(window,.03)-window)*pressure end}
require=function(m)
 if m==gameBallModule then return {GameBall=gameBall} end
 assert(m==replicatorModule);return {BallReplicator=provider}
end
local simCalls=0;local speedScale=1
provider.SimulateFrom=function(_,sample,age,target)
 simCalls=simCalls+1
 local position=sample.position+sample.direction*sample.speed*speedScale*age
 if (sample.position-target):Dot(position-target)<0 then return target end
 return position
end
'''

AFTER_INFO = '''
assert(gi.setup({Utils=u}))
local fires=0;local firedAt,firedDistance
local cd={source='local',blocking=false}
local cooldown={getDeflectCooldownState=function() return cd end,recordDeflectAttempt=function(at) cd.pressAt=at end}
local remote={fireParry=function(_,guard)
 if not guard() then return false end
 fires=fires+1;firedAt=tm;firedDistance=gi.getParrySnapshot(tm).position.Magnitude;return true
end}
'''

AFTER_AP = '''
assert(ap.setup({Utils=u,GameInfo=gi,Remote=remote,Cooldown=cooldown}))
assert(ap.bindCharacter(character))
local seq=0
local function publish(distance,speed,age,visual)
 seq=seq+1
 local sample={position=v(distance+speed*speedScale*(age or 0)),direction=v(-1),speed=speed,
  accel=0,maxSpeed=600,serverTime=tm-(age or 0),targetId=42,curveTime=1,curveTimeMax=1}
 provider.hasState=true;provider.lastSeq=seq;provider.history={sample}
 provider.syncData={RealPosition=sample.position,ForcedDirection=sample.direction,Speed=speed,TargetPlayerID=42}
 ball.Position=v(visual or distance);ball.AssemblyLinearVelocity=v()
 assert(gi.applyPacket({Sequence=seq,ServerTime=sample.serverTime,RealPosition=sample.position,
  ForcedDirection=sample.direction,Speed=speed,Accel=0,MaxSpeed=600,TargetPlayerID=42}))
end
'''


class AdaptiveParry(unittest.TestCase):
    def check(self, case):
        info = module('aux/gameinfo.luau').replace('local mod=', 'local gi=', 1)
        ap = module('autoparry.luau').replace('local mod=', 'local ap=', 1)
        run_case(COMMON + GAME_INFO + SETUP + info + AFTER_INFO + ap + AFTER_AP + case)

    def test_windows_match_dump_and_clash_pressure(self):
        self.check('''
assert(math.abs(gi.getDeflectWindow(16)-.85)<1e-9)
assert(math.abs(gi.getDeflectWindow(308)-.525)<1e-9)
assert(math.abs(gi.getDeflectWindow(600)-.2)<1e-9)
clashing=true;assert(math.abs(gi.getDeflectWindow(600)-.32)<1e-9)
pressure=1;assert(math.abs(gi.getDeflectWindow(600)-.03)<1e-9)
''')

    def test_prediction_waits_for_visual_ball_in_range(self):
        self.check('''
ping=.05;publish(75,600,.1,200)
local raw=gi.getSnapshotAt(tm);local predicted=gi.getParrySnapshot(tm)
assert(raw.position.X==200 and math.abs(predicted.position.X-75)<1e-8)
assert(predicted.predicted and predicted.predictionAge>.09)
local calls=simCalls;assert(gi.getParrySnapshot(tm)==predicted and simCalls==calls,'prediction cache recomputed same frame')
frame:Fire(1/60);assert(fires==0,'distant visual ball allowed a ghost click')
tm=tm+.2;publish(75,600,0,75);frame:Fire(1/60)
assert(fires==1 and firedDistance>4,'nearby ball did not recover')
''')

    def test_new_packet_before_replicator_callback_keeps_simulation_metadata(self):
        self.check('''
publish(300,600,0,300)
local encoded={};local oldTypeof=typeof
typeof=function(value) if value==encoded then return 'buffer' end return oldTypeof(value) end
bit32={btest=function(flags,mask) return math.floor(flags/mask)%2==1 end}
local fields={[3]=tm-.05,[11]=105,[23]=-1,[35]=600,[39]=7,[43]=600,[47]=.2,[51]=1,
 [55]=42,[63]=42,[75]=1,[83]=99,[92]=.5}
buffer={len=function() return 96 end,readu8=function(_,offset) return offset==0 and 128 or 2 end,
 readu16=function() return 2 end,readf32=function(_,offset) return fields[offset] or 0 end,
 readf64=function(_,offset) return fields[offset] or 0 end}
local decoded=gi.decodeBallPacket(encoded)
assert(decoded.NoSpeedFeel and decoded.CurveTime==.2 and decoded.CurveTimeMax==1)
assert(decoded.CurveAxis.Y==1 and decoded.BouncesLeft==2 and decoded.FlightTime==.5)
assert(gi.applyPacket(decoded));assert(provider.lastSeq==1)
frame:Fire(1/60)
assert(fires==0,'new packet bypassed the distant visual ball')
''')

    def test_visual_ball_near_kill_radius_cannot_force_an_early_click(self):
        self.check('''
publish(250,600,0,4)
frame:Fire(1/60);assert(fires==0,'visual grace position overrode authoritative state')
publish(75,600,0,250);frame:Fire(1/60)
assert(fires==0,'distant visual ball allowed a ghost click')
tm=tm+.2;publish(75,600,0,75);frame:Fire(1/60)
assert(fires==1,'failed to click when both positions entered window')
''')

    def test_high_speed_crosses_window_before_kill_at_multiple_frame_rates(self):
        for fps in (30, 60, 144, 240):
            with self.subTest(fps=fps):
                self.check(f'''
ping=.05
local distance=220
for i=1,200 do
 publish(distance,600,.05,distance+70)
 frame:Fire(1/{fps})
 if fires>0 then break end
 tm=tm+1/{fps};distance=distance-600/{fps}
end
assert(fires==1 and firedDistance>8.5,'fast ball reached raw range before dispatch')
local arrivalDistance=firedDistance-600*ping
assert(arrivalDistance>4,'dispatch could not reach server before kill radius')
local timeToRange=(arrivalDistance-8.5)/600
assert(timeToRange>=0 and timeToRange<.2,'dispatch preceded valid server window')
''')

    def test_pressure_window_does_not_use_old_point_25_seconds(self):
        self.check('''
clashing=true;pressure=1
publish(70,600,0,70);frame:Fire(1/60);assert(fires==0,'clicked before the 30ms pressured window')
publish(33,600,0,33);frame:Fire(1/60);assert(fires==0,'frame compensation exceeded the valid server window')
publish(25,600,0,25);frame:Fire(1/60);assert(fires==1,'did not use pressured window')
''')

    def test_frozen_ball_does_not_consume_the_window(self):
        self.check('''
gi.getBallFrozen=function() return true end
publish(30,600,0,30);frame:Fire(1/60);assert(fires==0,'frozen ball consumed parry window')
gi.getBallFrozen=function() return false end
tm=tm+.02;publish(30,600,0,30);frame:Fire(1/60)
assert(fires==1,'AP did not recover when ball resumed')
''')

    def test_factor_adapts_to_kill_margin_and_frame_budget(self):
        self.check('''
publish(200,16,0,200);frame:Fire(1/60)
local slow=ap.getTiming(gi.getSnapshotAt(tm))
assert(math.abs(slow.windowFactor-.4)<1e-9)
publish(200,600,0,200);frame:Fire(1/60)
local fast=ap.getTiming(gi.getSnapshotAt(tm))
assert(fast.windowFactor>.4 and fast.windowFactor<=.85 and fast.safetyRisk>0)
frame:Fire(1/30);local lowFps=ap.getTiming(gi.getSnapshotAt(tm))
assert(lowFps.windowFactor>=fast.windowFactor,'longer frame did not increase safety')
assert(math.abs(ap.getDefenseState(gi.getSnapshotAt(tm)).triggerDistance-lowFps.triggerDistance)<1e-9)
publish(4.1,600,0,4.1)
local imminent=ap.getTiming(gi.getSnapshotAt(tm))
assert(imminent.windowFactor>lowFps.windowFactor and imminent.timeToKill<lowFps.timeToKill,'proximity to death did not raise factor')
''')

    def test_motion_away_outside_raw_range_does_not_consume_parry(self):
        self.check('''
publish(20,600,0,20);provider.history[1].direction=v(1)
frame:Fire(1/60);assert(fires==0,'outgoing trajectory consumed the window')
tm=tm+.02;publish(8,600,0,8);provider.history[1].direction=v(1)
frame:Fire(1/60);assert(fires==1,'raw radius emergency was blocked by trajectory')
''')

    def test_client_throttle_retry_does_not_wait_fifty_milliseconds(self):
        self.check('''
local dispatch=remote.fireParry;local attempts=0
remote.fireParry=function(...)
 attempts=attempts+1;if attempts==1 then return false,'client throttle' end
 return dispatch(...)
end
gi.getAutoSpamDelay=function() return .008 end
publish(50,600,0,50);frame:Fire(1/240);assert(fires==0)
tm=tm+.009;publish(44.6,600,0,44.6);frame:Fire(1/240)
assert(fires==1 and attempts==2,'retry slept through the incoming ball')
''')


if __name__ == '__main__':
    unittest.main()
