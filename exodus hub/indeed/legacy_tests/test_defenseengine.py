"""Real modular defense stack: observations, geometry, cooldown, AP and transport.

Only Roblox instances, network events and native abilities are doubles. No second
implementation of the AP policy and no extraction of private engine functions.
"""
import unittest
from test_logic_reliability import COMMON, GAME_INFO, module, run_case

FIXTURE = COMMON + GAME_INFO + r'''
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
local oldIndex=V.__index
V.__index=function(t,k) if k=='Unit' then return t/t.Magnitude end return oldIndex(t,k) end
Color3={fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end}
local pre,post,heart,changed=signal(),signal(),signal(),{}
local attrs={MatchStatus=6,CurGamemode=0,GameBallTarget=99}
world.GetAttribute=function(_,key) return attrs[key] end
world.GetServerTimeNow=function() return tm end
world.GetAttributeChangedSignal=function(_,key) changed[key]=changed[key] or signal();return changed[key] end
world.DescendantAdded,world.DescendantRemoving=signal(),signal()
ball.Transparency,ball.LocalTransparencyModifier=0,0
ball.Color=Color3.fromRGB(153,153,153)
ball.GetAttribute=function() end
ball.GetPropertyChangedSignal=function() return signal() end
root.AssemblyLinearVelocity=v()
character.AncestryChanged=signal()
local hum={Health=100,Died=signal()}
character.FindFirstChildOfClass=function() return hum end
local pa={Lives=3,Playing=true,DeflectRange=8.5}
player.GetAttribute=function(_,key) return pa[key] end
player.GetNetworkPing=function() return 0 end
local players={LocalPlayer=player,GetPlayers=function() return {player} end,GetPlayerByUserId=function(_,id) if id==42 then return player end end}
local calls,rejected,accept,afterGuard=0,0,true,nil
local ability={Cooldown=0,LastDeflectCallAt=0,ClickInstances={}}
function ability:Deflect()
 if not accept then rejected=rejected+1;return end
 calls=calls+1;self.LastDeflectCallAt=tm
 if afterGuard then afterGuard() end
end
local fierceCalls=0
local fierce={Cooldown=0,ActivateAndBlock=function() fierceCalls=fierceCalls+1;return true end}
local abilitiesModule=instance('ModuleScript')
shared.children.Abilities=instance('Folder',{ClientAbilities=abilitiesModule})
local originalRequire=require
require=function(m) if m==abilitiesModule then return {Abilities={[1]=ability,[19]=fierce}} end return originalRequire(m) end
game={PlaceId=12979690461,GetService=function(_,name) if name=='ReplicatedStorage' then return storage elseif name=='Players' then return players end end}
workspace=world
local enabled,spam=false,false
local cfg={AutoParry=true,AutoParryWindowFactor=.3,AutoFierce=true,ClickMethod='Deflect'}
u.getPlayers=function() return players end
u.getLocalPlayer=function() return player end
u.getRunService=function() return {PreSimulation=pre,PostSimulation=post,Heartbeat=heart} end
u.getConfigValue=function(key) return cfg[key] end
u.isActive=function() return enabled end
u.isSpamActive=function() return spam end
u.trackGlobal=function() end;u.untrackGlobal=function() end;u.trackCharacter=function() end;u.untrackCharacter=function() end
u.apiVersion=function() return 1 end
u.recordError=function(_,detail) error(detail) end
local serverCooldown,parried=signal(),signal()
'''

def named(path, name):
    return module(path).replace('local mod=', f'local {name}=', 1)

STACK = (FIXTURE + named('game/gameinfo.luau','info') + named('combat/deflectgeometry.luau','geom')
         + named('combat/cooldown.luau','cd') + named('combat/remote.luau','transport')
         + named('combat/autoparry.luau','ap') + named('combat/autofierce.luau','af') + r'''
assert(info.setup({Utils=u}))
assert(geom.setup({Utils=u,GameInfo=info}))
cd.getDeflectServerEvents=function() return {cooldown=serverCooldown,parried=parried} end
assert(cd.setup({Utils=u,GameInfo=info}))
assert(transport.setup({Utils=u,GameInfo=info}))
local opportunity,beforeSend=0,nil
local auto={onDefenseOpportunity=function() opportunity=opportunity+1;if beforeSend then beforeSend() end end,
 stopSpam=function() spam=false end}
assert(ap.setup({Utils=u,GameInfo=info,DeflectGeometry=geom,Cooldown=cd,Remote=transport,AutoSpam=auto}))
assert(ap.bindCharacter(character))
info.installBallWatcher(function() end,ap.onBallSync)
enabled=true
local seq=0
local function packetTo(target,distance,dt)
 tm=tm+(dt or .01);seq=(seq+1)%65536
 ball.Position=v(distance or 10);ball.AssemblyLinearVelocity=v(-100)
 local p=packet(seq,target);p.RealPosition=ball.Position;p.ServerTime=tm
 assert(info.applyPacket(p));ap.onBallSync(p)
end
local function tick(dt)
 tm=tm+(dt or .01);post:Fire(dt or .01)
end
local function startFierce()
 assert(af.setup({Utils=u,GameInfo=info,DeflectGeometry=geom,Cooldown=cd,Remote=transport,AutoSpam=auto,AutoParry=ap}))
end
''')

class DefenseEngineTests(unittest.TestCase):
    def check(self, case): run_case(STACK + case)

    def test_new_packet_overrides_stale_attribute_and_one_click_per_flight(self):
        self.check('''
packetTo(42);assert(calls==1)
for i=1,20 do packetTo(42) end
assert(calls==1,'duplicate inbound samples repeated a click')
packetTo(99);packetTo(42);assert(calls==2,'genuine return must rearm')
''')
    def test_native_refusal_does_not_spend_the_flight_or_add_a_retry_delay(self):
        self.check('''
accept=false;packetTo(42);assert(calls==0 and rejected==1)
accept=true;tick(.001);assert(calls==1,'AP waited after client became ready')
tick();assert(calls==1)
''')
    def test_completed_miss_retries_same_target_immediately(self):
        self.check('''
afterGuard=function() ability.Cooldown=.2;ability.PendingPressAt=tm;ability.PendingPredictUntil=tm+.08 end
packetTo(42);assert(calls==1);assert(cd.getDeflectCooldownState().blocking)
tick(.1);assert(calls==1)
afterGuard=nil;ability.Cooldown=0;tick(.11)
assert(calls==2,'same target was permanently spent after cooldown')
tick();assert(calls==2,'old miss outcome spent two clicks')
''')
    def test_success_reset_is_not_itself_a_new_flight(self):
        self.check('''
packetTo(42);parried:Fire();post:Fire(.016);assert(calls==1)
packetTo(42);assert(calls==2,'confirmed parry plus later incoming packet should recover')
for i=1,10 do packetTo(42) end
assert(calls==2,'one confirmation was reused')
''')
    def test_delayed_parry_confirmation_cannot_rearm_an_older_inbound_sample(self):
        self.check('''
packetTo(42);packetTo(42);assert(calls==1)
tm=tm+.03;parried:Fire();post:Fire(.016)
assert(calls==1,'a pre-confirmation inbound packet fabricated a new flight')
packetTo(42);assert(calls==2)
''')
    def test_spam_has_exclusive_send_and_ap_observes_while_suppressed(self):
        self.check('''
spam=true;packetTo(42);assert(calls==0)
spam=false;post:Fire(.016);assert(calls==1,'AP delayed handover')
spam=true;packetTo(99);packetTo(42);assert(calls==1)
spam=false;post:Fire(.016);assert(calls==2,'AP missed return while spam owned dispatch')
''')
    def test_final_guard_stops_spam_race_and_retries_without_latching(self):
        self.check('''
local n=0;beforeSend=function() n=n+1;if n==2 then spam=true end end
packetTo(42);assert(calls==0)
beforeSend=nil;spam=false;post:Fire(.016);assert(calls==1)
''')
    def test_blocking_cooldown_prevents_first_click_and_ready_resumes(self):
        self.check('''
ability.Cooldown=.4;packetTo(42);assert(calls==0)
ability.Cooldown=0;post:Fire(.016);assert(calls==1)
''')
    def test_death_detach_and_old_callbacks_cannot_send(self):
        self.check('''
packetTo(42,1000);assert(calls==0)
hum.Health=0;hum.Died:Fire();packetTo(42);post:Fire(.016);assert(calls==0)
hum.Health=100;attrs.MatchStatus=1;info.getGameContext();attrs.MatchStatus=6
root.Position=v(30);assert(ap.bindCharacter(character));packetTo(42,40);assert(calls==1)
ap.detachCharacter();packetTo(99);packetTo(42);post:Fire(.016);assert(calls==1)
''')
    def test_disabled_ap_and_inactive_round_block_sends(self):
        self.check('''
cfg.AutoParry=false;packetTo(42);assert(calls==0)
cfg.AutoParry=true;attrs.MatchStatus=1;tick();assert(calls==0)
''')
    def test_no_private_native_hook_or_game_ui_is_installed(self):
        self.check('''
local original=provider.ApplySnapshot
packetTo(42);assert(provider.ApplySnapshot==original)
ap.teardown();assert(provider.ApplySnapshot==original)
assert(not storage.children.ScreenGui)
''')
    def test_fierce_rescues_reversible_cooldown_before_pending_window_ends(self):
        self.check('''
startFierce();ability.Cooldown=1;ability.PendingPressAt=tm;ability.PendingPredictUntil=tm+.3
packetTo(42);assert(calls==0);assert(not cd.getDeflectCooldownState().miss)
af.onBallSync();assert(fierceCalls==1,'Fierce waited for miss while impact was imminent')
af.onBallSync();assert(fierceCalls==1,'Fierce repeated the same episode')
''')
    def test_fierce_never_replaces_ready_parry(self):
        self.check('''
startFierce();packetTo(42);af.onBallSync();assert(calls==1 and fierceCalls==0)
''')
    def test_fierce_rechecks_finished_cooldown_before_dispatch(self):
        self.check('''
startFierce();ability.Cooldown=1;packetTo(42)
local native=transport.fireFierce
transport.fireFierce=function(guard) ability.Cooldown=0;return native(guard) end
af.onBallSync();assert(fierceCalls==0)
post:Fire(.016);assert(calls==1)
''')
    def test_geometry_rejects_near_tangent_that_never_enters_radius(self):
        self.check('''
packetTo(42,20);assert(calls==1)
packetTo(99);ball.AssemblyLinearVelocity=v(0,100)
-- Direct shared timing query, with an unambiguous target and valid motion.
local value={position=v(20),velocity=v(0,100),speed=100,syncSpeed=100,targeted=true}
local t=geom.getParryTiming(value,v(),{factor=.85,ping=0,frameLead=.016})
assert(not t.ready and t.timeToRange==math.huge,'tangent sphere projection fabricated contact')
''')

class SharedDefenseTests(unittest.TestCase):
    def check(self, case): run_case(STACK+case)
    def test_latest_attribute_can_override_older_packet(self):
        self.check('''
packetTo(99);assert(calls==0)
tm=tm+.01;attrs.GameBallTarget=42;changed.GameBallTarget:Fire();assert(calls==1)
packetTo(99);assert(calls==1,'older attribute overrode newer outgoing packet')
''')
    def test_expired_exchange_evidence_is_not_reported_as_current(self):
        self.check('''
packetTo(99);tm=tm+.6
local value=info.getSnapshotAt(tm);assert(value.exchangeTargetId==-1)
''')
    def test_shared_simulation_is_cached_for_ap_and_fierce(self):
        self.check('''
local simulations=0
provider.SimulateFrom=function(_,sample,age,target) simulations=simulations+1;return sample.position+sample.direction*sample.speed*age end
provider.hasState=true
packetTo(42,100)
-- An authoritative packet can precede the provider callback.
local sample={seq=seq,serverTime=tm,position=v(100),direction=v(-1),speed=100,targetId=42}
provider.lastSeq=seq;provider.history={sample}
tm=tm+.005
local before=simulations;local a=info.getParrySnapshot(tm);local b=info.getParrySnapshot(tm)
assert(a.predicted and a==b and simulations-before==2,'consumers repeated the same trajectory simulation')
''')
    def test_spam_native_press_does_not_block_ap_handover_as_a_manual_click(self):
        self.check('''
spam=true;packetTo(42);tm=tm+.001;ability.LastDeflectCallAt=tm
spam=false;post:Fire(.016);assert(calls==1)
''')
    def test_manual_click_is_respected_without_pausing_after_manual_fierce(self):
        self.check('''
packetTo(42,1000);tm=tm+.001;ability.LastDeflectCallAt=tm
packetTo(42);assert(calls==0,'AP duplicated a manual click in the same flight')
packetTo(99);assert(ap.beginFierce());packetTo(42);assert(calls==1,'manual Fierce unnecessarily paused AP')
''')
    def test_manual_miss_retries_immediately_after_cooldown(self):
        self.check('''
packetTo(42,1000);tm=tm+.001
ability.LastDeflectCallAt=tm;ability.PendingPressAt=tm;ability.PendingPredictUntil=tm+.08;ability.Cooldown=.2
packetTo(42);assert(calls==0)
ability.Cooldown=0;tm=tm+.21;packetTo(42)
assert(calls==1,'manual miss blocked the entire flight')
''')
    def test_recovery_state_prioritizes_ready_deflect_and_keeps_pending_distinct_from_miss(self):
        self.check('''
ability.Cooldown=1;ability.PendingPressAt=tm;ability.PendingPredictUntil=tm+.2
local r=cd.getDeflectRecoveryState(.05,0)
assert(r.needsFierce and not r.cooldown.miss)
ability.Cooldown=0;r=cd.getDeflectRecoveryState(0,0)
assert(r.ready and not r.needsFierce)
''')
    def test_confirmed_cooldown_observer_ignores_teardown(self):
        self.check('''
local notices=0;local connection=cd.observeDeflect(function() notices=notices+1 end)
serverCooldown:Fire(1,5.93848805167512e76,.2);assert(notices==1)
connection:Disconnect();serverCooldown:Fire(1,6.60750295352893e76,0);assert(notices==1)
cd.teardown();serverCooldown:Fire(1,5.93848805167512e76,.2);assert(notices==1)
''')

TRAINING_BUILD = r'''
local trainingCalls=0
local trainingBall=instance('BasePart');trainingBall.Position=v(10);trainingBall.AssemblyLinearVelocity=v(-100)
local zone=instance('BasePart');zone.Size=v(100,100,100);zone.CFrame={PointToObjectSpace=function(_,position) return position end}
world.children.Training=instance('Folder',{Areas=instance('Folder',{Zone=zone}),TrainingClient=instance('Folder',{TrainingBall=trainingBall})})
local trainState,trainEvent=instance('RemoteEvent'),instance('RemoteEvent')
trainState.OnClientEvent,trainEvent.OnClientEvent=signal(),signal()
local block=instance('RemoteEvent');block.FireServer=function() trainingCalls=trainingCalls+1 end
storage.children.Training=instance('Folder',{Remotes=instance('Folder',{BallState=trainState,Event=trainEvent,Block=block})})
world.CurrentCamera={CFrame={Position=v(),LookVector=v(-1)}}
pa.Lives=0
'''

class TrainingDefenseTests(unittest.TestCase):
    def check(self, case):
        stack=STACK.replace('assert(info.setup({Utils=u}))',TRAINING_BUILD+'assert(info.setup({Utils=u}))')
        run_case(stack + r'''
info.bindBallSync(function() end)
local function trainingPacket(target)
 tm=tm+.01;trainState.OnClientEvent:Fire(v(10),v(-100),tm,target,nil,100)
end
'''+case)

    def test_training_uses_shared_observer_and_block_remote(self):
        self.check('''
trainingPacket(42);assert(trainingCalls==1 and calls==0)
trainingPacket(42);assert(trainingCalls==1)
trainEvent.OnClientEvent:Fire('Parry',42);trainingPacket(99);trainingPacket(42)
assert(trainingCalls==2,'training return did not rearm')
''')
    def test_training_retries_after_actual_miss_cooldown(self):
        self.check('''
trainingPacket(42);assert(trainingCalls==1)
tm=tm+.5;trainingPacket(42);assert(trainingCalls==1)
tm=tm+1;trainingPacket(42);assert(trainingCalls==2,'training miss cooldown never released shot')
''')
    def test_training_is_independent_of_match_spam(self):
        self.check('''
spam=true;trainingPacket(42);assert(trainingCalls==1)
ap.detachCharacter();trainingPacket(99);trainingPacket(42);assert(trainingCalls==1)
''')

if __name__ == '__main__': unittest.main()
