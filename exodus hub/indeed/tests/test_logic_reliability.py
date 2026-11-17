"""Targeted behavioral regressions for packet ordering, lifecycle and scheduling.

Uses the same Lua runtime as CI; engine APIs are explicit test doubles.
"""
import re
import os
import subprocess
import tempfile
import unittest

from test_raw_target_parry import ROOT, run_lua


def run_case(script):
    binary = os.environ.get('LUAU_BIN')
    if not binary:
        return run_lua(script)
    with tempfile.NamedTemporaryFile(mode='w', suffix='.luau') as fixture:
        fixture.write('local math=table.clone(math);local os=table.clone(os);local table=table.clone(table)\n' + script)
        fixture.flush()
        result = subprocess.run([binary, fixture.name], capture_output=True, text=True, timeout=10)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)


def module(path):
    source = (ROOT / path).read_text()
    if path == 'aux/gameinfo.luau':
        dependencies = (module('aux/ballsync.luau').replace('local mod=', 'local TestBallSync=', 1)
                        + module('aux/deflectgeometry.luau').replace('local mod=', 'local TestGeometry=', 1))
        source = source.replace('function GameInfo.setup(deps)',
            'function GameInfo.setup(deps)\n deps.BallSync=TestBallSync')
        start = source.index('function GameInfo.setup(deps)')
        end = source.index('function GameInfo.getBall()', start)
        setup = source[start:end].replace('  return true\nend',
            '  GameInfo._geometry=TestGeometry; return TestGeometry.setup({GameInfo=GameInfo,Utils=deps.Utils})\nend')
        source = dependencies + source[:start] + setup + source[end:]
    if path in ('autoparry.luau', 'autospam.luau', 'extras/autofierce.luau', 'extras/autodash.luau'):
        # Existing fixtures provide geometry doubles alongside game data. Production
        # obtains a separate service through Permissions.resolve.
        dependencies = module('aux/deflectgeometry.luau').replace('local mod=', 'local TestGeometry=', 1)
        marker = re.search(r'function (\w+)\.setup\(deps\)', source).group(0)
        wiring = """
 if deps and deps.GameInfo and not deps.DeflectGeometry then
  local g=deps.GameInfo
  deps.DeflectGeometry=g._geometry or setmetatable({}, {__index=function(_,name)
   if g[name] then return g[name] end
   if name=='getAutoParryGeometry' and g.getDeflectGeometry then
    return function(speed,factor,frame,ping) return g.getDeflectGeometry(speed,'ap',factor,false,ping) end
   end
   return TestGeometry[name]
  end})
 end
"""
        source = dependencies + source.replace(marker, marker + wiring)
    if not os.environ.get('LUAU_BIN'):
        source = re.sub(
            r'([A-Za-z_][\w.]*) ([+\-*/%])= ([^;\n]+?)(?=;|\n| end| else\b)',
            lambda m: f'{m[1]} = {m[1]} {m[2]} ({m[3]})', source,
        )
    return 'local mod=(function()\n' + source + '\nend)()\n'


COMMON = '''
local tm=10; os.clock=function() return tm end
math.clamp=function(x,a,b) return math.max(a,math.min(b,x)) end
table.clone=function(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
table.clear=function(t) for k in pairs(t) do t[k]=nil end end
table.find=function(t,x) for k,v in ipairs(t) do if v==x then return k end end end
warn=function() end
local function signal()
 local s={listeners={}}
 function s:Connect(fn)
  local c={Connected=true,callback=fn};self.listeners[c]=true
  function c:Disconnect() self.Connected=false;s.listeners[self]=nil end
  return c
 end
 function s:Fire(...) for c in pairs(table.clone(self.listeners)) do if c.Connected then c.callback(...) end end end
 return s
end
local V={}
V.__index=function(t,k)
 if k=='Magnitude' then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z) end
 return V[k]
end
local function v(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},V) end
V.__add=function(a,b) return v(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
V.__sub=function(a,b) return v(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
V.__mul=function(a,b) return v(a.X*b,a.Y*b,a.Z*b) end
V.__div=function(a,b) return v(a.X/b,a.Y/b,a.Z/b) end
Vector3={new=v,zero=v()}
function typeof(x)
 if getmetatable(x)==V then return 'Vector3' end
 if type(x)=='table' and x.instance then return 'Instance' end
 return type(x)
end
local function instance(class, children)
 local t={instance=true,Parent=true,children=children or {}}
 function t:IsA(kind) return kind==class end
 function t:FindFirstChild(name) return self.children[name] end
 return t
end
'''

GAME_INFO = '''
local ball=instance('BasePart');ball.Position=v(20);ball.AssemblyLinearVelocity=v(-100)
local root=instance('BasePart');root.Position=v()
local character=instance('Model',{HumanoidRootPart=root})
local player={UserId=42,Character=character,GetAttribute=function() end}
local provider={hasState=false}
local replicatorModule=instance('ModuleScript')
require=function(m) assert(m==replicatorModule);return {BallReplicator=provider} end
local shared=instance('Folder',{Gameplay=instance('Folder',{BallReplicator=replicatorModule})})
local storage=instance('Folder',{Shared=shared})
local world=instance('Workspace',{GameBall=ball})
world.GetAttribute=function() end
local u={now=os.clock,getPlayers=function() return {LocalPlayer=player} end,
 getWorkspace=function() return world end,getReplicatedStorage=function() return storage end}
local function packet(seq,target)
 return {Sequence=seq,TargetPlayerID=target or 42,Speed=100,RealPosition=v(20),ForcedDirection=v(-1)}
end
'''


class PacketReliability(unittest.TestCase):
    def check(self, case):
        run_case(COMMON + GAME_INFO + module('aux/gameinfo.luau') +
                'assert(mod.setup({Utils=u}))\n' + case)

    def test_order_survives_expiration_and_wraparound(self):
        self.check('''
assert(mod.applyPacket(packet(65535)))
assert(not mod.applyPacket(packet(65535)))
assert(mod.applyPacket(packet(0)))
tm=11;assert(mod.getSyncSequence()==0,'expiration erased sequence watermark')
assert(not mod.applyPacket(packet(65534)),'old packet accepted after expiration')
assert(not mod.applyPacket(packet(32768)),'ambiguous half-range accepted')
assert(mod.applyPacket(packet(1)))
assert(mod.applySync(packet(0/0))==nil)
assert(mod.applySync(packet('2'))==nil)
assert(mod.applySync(packet(1.5))==nil)
''')

    def test_provider_listener_order_and_duplicate_refresh(self):
        self.check('''
provider.hasState=true;provider.lastSeq=8;provider.syncData=packet(8)
assert(mod.applyPacket(packet(8)),'provider callback ran first and discarded valid packet')
tm=10.6
assert(mod.applySync(nil)==nil,'duplicate provider state was refreshed')
assert(mod.getSnapshotAt(tm).targetUncertain,'old target remained confirmed')
provider.lastSeq=9;provider.syncData=packet(9,99)
assert(mod.applySync(nil).Sequence==9)
assert(not mod.getSnapshotAt(tm).targetUncertain)
assert(mod.getSnapshotAt(tm).targetId==99)
assert(not mod.applyPacket(packet(8)),'old packet overrode provider')
tm=11.2;assert(mod.applySync(packet(9))==nil)
assert(mod.getSnapshotAt(tm).targetUncertain,'duplicate packet renewed freshness')
assert(mod.applySync(packet(10,88)))
assert(mod.getSnapshotAt(tm).targetId==88,'older provider state overrode the accepted table packet')
tm=11.8;assert(mod.getSnapshotAt(tm).targetId==88 and mod.getSnapshotAt(tm).targetUncertain)
''')

    def test_packet_snapshots_expire_without_a_provider(self):
        self.check('''
assert(mod.applyPacket(packet(7)))
local a=mod.getSnapshotAt(tm);assert(mod.isSnapshotValid(a) and not a.targetUncertain)
tm=10.6;local b=mod.getSnapshotAt(tm)
assert(mod.isSnapshotValid(b) and b.targetUncertain)
assert(mod.getSyncSequence()==7)
assert(mod.applyPacket(packet(8,99)))
assert(mod.getSnapshotAt(tm).targetId==99 and not mod.getSnapshotAt(tm).targetUncertain)
''')


class CooldownReliability(unittest.TestCase):
    def test_server_only_miss_remote_replacement_and_stale_callbacks(self):
        run_case(COMMON + '''
local heartbeat=signal();local activeSignal=signal();local parried=signal()
local u={getRunService=function() return {Heartbeat=heartbeat} end,
 getReplicatedStorage=function() return instance('Folder') end,
 trackGlobal=function() end,untrackGlobal=function() end,recordError=function() end}
local info={getDeflectAbility=function() end}
''' + module('aux/cooldown.luau') + '''
mod.getDeflectServerEvents=function() return {cooldown=activeSignal,parried=parried} end
assert(mod.setup({Utils=u,GameInfo=info}))
mod.recordDeflectAttempt(tm)
activeSignal:Fire(1,5.93848805167512e76,.2)
local oldConnection=next(activeSignal.listeners)
assert(mod.getDeflectCooldownState().blocking)
assert(mod.getDeflectCooldownState().miss,'server-only miss not recorded')
tm=10.3;assert(not mod.getDeflectCooldownState().blocking)
assert(mod.getDeflectCooldownState().miss,'miss lost before retry')
activeSignal=signal();tm=10.6;mod.getDeflectCooldownState()
assert(not oldConnection.Connected,'obsolete remote stayed connected')
oldConnection.callback(1,5.93848805167512e76,100)
assert(mod.getDeflectCooldownState().source=='unknown','old callback changed replacement state')
activeSignal:Fire(1,5.93848805167512e76,.2)
assert(mod.getDeflectCooldownState().blocking)
mod.teardown();oldConnection.callback(1,5.93848805167512e76,100)
assert(mod.getDeflectCooldownState()==nil)
''')


SPAM = '''
local mode,rate,active,manual='CPS',200,true,true
local threads={};local count=0;local beforeSend
task={wait=function() coroutine.yield() end,delay=function() end,defer=function() end}
function task.spawn(fn) local co=coroutine.create(fn);threads[#threads+1]=co;assert(coroutine.resume(co));return co end
local function frame(dt)
 tm=tm+dt
 for _,co in ipairs(table.clone(threads)) do
  if coroutine.status(co)=='suspended' then local ok,err=coroutine.resume(co);assert(ok,err) end
 end
end
local u={apiVersion=function() return 1 end,getConfigValue=function(k) if k=='SpamRateMode' then return mode end return rate end,
 isActive=function() return active end,isManualSpamActive=function() return manual end,isAutoSpamActive=function() return false end,
 observeSpam=function() return {Disconnect=function() end} end,observeConfig=function() return {Disconnect=function() end} end,
 trackGlobal=function() end,untrackGlobal=function() end,recordTransition=function() end,recordError=function(_,e) error(e) end}
local r={fireParry=function(_,guard) assert(guard());count=count+1;if beforeSend then beforeSend() end return true end}
local delay=0
local g={getAutoSpamDelay=function() return delay end,getMinimumSpamInterval=function() return .0301 end}
local a={canSend=function() return false end,canSendManual=function() return manual end}
'''


class SpamReliability(unittest.TestCase):
    def check(self, case):
        run_case(COMMON + SPAM + module('spam.luau') + case)

    def test_lag_and_extreme_rates_have_bounded_work(self):
        for mode, rate in [('CPS', '1e300'), ('CPF', '1e300'), ('MS', '1e-300')]:
            with self.subTest(mode=mode):
                self.check(f"mode='{mode}';rate={rate}\n" + '''
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
frame(10);assert(count==128,'unbounded requests after lag or extreme rate')
manual=false;frame(.016);assert(count==128)
mod.teardown()
''')

    def test_cancellation_stops_the_current_burst(self):
        self.check('''
mode='CPF';rate=100
beforeSend=function() manual=false end
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
frame(.016);assert(count==1,'cancellation did not stop burst')
mod.teardown()
''')

    def test_auto_uses_ability_delay_and_minimum_interval(self):
        self.check('''
mode='Auto'
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
for i=1,240 do frame(1/240) end
assert(count>=30 and count<=34,'Auto ignored minimum interval')
delay=.2;local previous=count
frame(.3);assert(count==previous,'Auto ignored ability delay')
delay=nil;frame(.04);assert(count==previous+1,'missing client ability blocked direct dispatch')
mod.teardown()
''')

    def test_metrics_count_more_than_256_requests_and_expire(self):
        self.check('''
mode='CPF';rate=10
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
for i=1,60 do frame(1/60) end
assert(count==600)
local status=mod.getStatus()
assert(status.attemptsLastSecond==600 and status.acceptedLastSecond==600,'metrics truncated high rates')
manual=false;frame(1.1)
assert(mod.getStatus().attemptsLastSecond==0 and mod.getStatus().acceptedLastSecond==0)
mod.teardown()
''')


class LifecycleReliability(unittest.TestCase):
    def test_auto_dark_and_jump_follow_external_config_without_duplicate_frames(self):
        for file, key in [('autodark', 'AutoDark'), ('universal/autojump', 'AutoJump')]:
            with self.subTest(module=file):
                run_case(COMMON + '''
Enum={Material={Air='Air'},HumanoidStateType={Jumping='Jumping'}}
local frame=signal();local changes=signal();local enabled=false
local u={getConfigValue=function() return enabled end,isActive=function() return true end,
 getLocalPlayer=function() return {} end,getWorkspace=function() return {} end,
 getRunService=function() return {Heartbeat=frame} end,observeConfig=function(fn) return changes:Connect(fn) end,
 trackGlobal=function() end,untrackGlobal=function() end}
''' + module('extras/' + file + '.luau') + f'''
assert(mod.setup({{Utils=u,Remote={{}},GameInfo={{}}}}));assert(next(frame.listeners)==nil)
enabled=true;changes:Fire({{{key}=true}});assert(next(frame.listeners))
mod.sync();local count=0;for _ in pairs(frame.listeners) do count=count+1 end
assert(count==1,'sync duplicated frame connections')
enabled=false;changes:Fire({{{key}=false}});assert(next(frame.listeners)==nil)
mod.teardown();enabled=true;changes:Fire({{{key}=true}});assert(next(frame.listeners)==nil)
''')

    def test_camera_retained_wrapper_stops_after_teardown(self):
        run_case(COMMON + '''
local api={getRotation=function(value) return value end}
local input=instance('ModuleScript')
local playerModule=instance('ModuleScript',{CameraModule=instance('Folder',{CameraInput=input})})
local scripts=instance('Folder',{PlayerModule=playerModule})
local player=instance('Player',{PlayerScripts=scripts})
require=function() return api end
task={spawn=function(fn) fn() end}
local changed=signal()
local u={getLocalPlayer=function() return player end,isActive=function() return true end,
 getConfigValue=function() return 1.5 end,observeConfig=function(fn) return changed:Connect(fn) end,
 trackGlobal=function() end,untrackGlobal=function() end}
''' + module('extras/universal/camera.luau') + '''
assert(mod.setup({Utils=u}));local retained=api.getRotation
assert(retained(2)==3)
mod.teardown();assert(api.getRotation(2)==2 and retained(2)==2,'stale wrapper kept applying sensitivity')
''')

    def test_dumper_cancel_callback_can_start_a_new_run(self):
        run_case(COMMON + '''task={spawn=function() end}\n''' + module('extras/universal/dumper.luau') + '''
assert(mod.start({onCanceled=function() assert(mod.start()) end}))
mod.stop();assert(mod.isRunning() and mod.getStatus().running,'canceling old dump corrupted new run status')
mod.stop();assert(not mod.isRunning() and not mod.getStatus().running)
''')

    def test_server_search_ignores_unrelated_teleport_failures(self):
        run_case(COMMON + '''
local failure=signal();local player={};local teleports,errors=0,0
local teleporter={TeleportInitFailed=failure,TeleportToPlaceInstance=function() teleports=teleports+1 end}
local http={JSONDecode=function() return {data={{id='best',playing=1,maxPlayers=10,ping=25}}} end}
game={PlaceId=42,JobId='current',GetService=function(_,name) if name=='TeleportService' then return teleporter else return http end end}
game.HttpGet=function() failure:Fire(player,nil,'old failure',42,{ServerInstanceId='previous'});return '{}' end
task={delay=function() end}
local u={getLocalPlayer=function() return player end,isActive=function() return true end,
 trackGlobal=function() end,untrackGlobal=function() end,recordError=function() errors=errors+1 end}
''' + module('extras/universal/servers.luau') + '''
assert(mod.setup({Utils=u}));assert(mod.hop());assert(teleports==1 and errors==0)
failure:Fire(player,nil,'old failure',42,{ServerInstanceId='previous'})
assert(not mod.rejoin(),'unrelated failure released current teleport')
failure:Fire(player,nil,'failed',42,{ServerInstanceId='best'})
assert(errors==1 and mod.rejoin());assert(teleports==2)
mod.teardown()
''')

    def test_panic_disables_combat_without_detaching_the_character(self):
        loader = (ROOT.parents[1] / 'loader.luau').read_text()
        callback = re.search(r'onPanic = function\(\)(.*?)\n    end,', loader, re.S).group(1)
        run_case(COMMON + '''
local bound,manual,stopped=true,true,false
local cfg={AutoParry=true,AutoSpam=true}
local utils={setConfig=function(p) for k,v in pairs(p) do cfg[k]=v end end,stopAllSpam=function() manual=false end}
local loaded={autoparry={resetState=function() bound=false end},autospam={stopSpam=function() stopped=true end}}
local function panic()
''' + callback + '''
end
panic();assert(bound and not manual and stopped and not cfg.AutoParry and not cfg.AutoSpam)
''')

    def test_gravity_tracks_config_value_changes_while_enabled(self):
        run_case(COMMON + '''
Enum={ActuatorRelativeTo={World='World'}}
local root={Parent=true,AssemblyMass=2,Anchored=false}
local humanoid={Health=100}
local character={FindFirstChildOfClass=function() return humanoid end,FindFirstChild=function() return root end}
local frame=signal();local changed=signal();local objects={}
local world={Gravity=196.2}
game={GetService=function(_,name) if name=='Workspace' then return world end return {PreSimulation=frame} end}
Instance={new=function(class)
 local t={class=class,Destroy=function(self) self.Parent=nil end};objects[#objects+1]=t;return t
end}
local cfg={UniversalGravityEnabled=true,UniversalGravity=100}
local u={getLocalPlayer=function() return {Character=character} end,getConfigValue=function(k) return cfg[k] end,
 trackGlobal=function() end,untrackGlobal=function() end,observeConfig=function(fn) return changed:Connect(fn) end}
function u.setConfig(p)
 local delta={};for k,v in pairs(p) do if cfg[k]~=v then cfg[k]=v;delta[k]=v end end
 if next(delta) then changed:Fire(delta) end;return true
end
''' + module('extras/universal/gravity.luau') + '''
assert(mod.setup({Utils=u}));assert(math.abs(objects[2].Force.Y-192.4)<1e-8)
u.setConfig({UniversalGravity=0});assert(math.abs(objects[2].Force.Y-392.4)<1e-8)
u.setConfig({UniversalGravity=400});assert(math.abs(objects[2].Force.Y+407.6)<1e-8)
mod.teardown();assert(not objects[1].Parent and not objects[2].Parent)
''')

    def test_fly_stops_during_yielding_control_load(self):
        run_case(COMMON + '''
Enum={KeyCode={},UserInputType={Touch='touch'}}
for _,key in ipairs({'W','S','A','D','E','Q','Space','LeftControl'}) do Enum.KeyCode[key]=key end
local root={Parent=true,AssemblyLinearVelocity=v()};local humanoid={Parent=true,Health=100,PlatformStand=false,AutoRotate=true}
local character={FindFirstChild=function() return root end,FindFirstChildOfClass=function() return humanoid end}
local scripts=instance('Folder',{PlayerModule=instance('ModuleScript')})
local player={Character=character,FindFirstChild=function() return scripts end}
local frame=signal();local changed=signal()
local input={TouchEnabled=true,InputBegan=signal(),InputEnded=signal(),WindowFocusReleased=signal(),
 GetFocusedTextBox=function() end,GetLastInputType=function() return 'touch' end}
local world={CurrentCamera={CFrame={RightVector=v(1),LookVector=v(0,0,-1)}}}
game={GetService=function(_,name)
 if name=='Workspace' then return world elseif name=='UserInputService' then return input else return {PreSimulation=frame} end
end}
local objects={}
Instance={new=function(class) local t={Destroy=function(self) self.Parent=nil end};objects[#objects+1]=t;return t end}
require=function() coroutine.yield();return {GetControls=function() return {GetMoveVector=function() return v() end} end} end
local cfg={UniversalFly=false,UniversalFlySpeed=1}
local u={getLocalPlayer=function() return player end,getConfigValue=function(k) return cfg[k] end,
 trackGlobal=function() end,untrackGlobal=function() end,observeConfig=function(fn) return changed:Connect(fn) end}
function u.setConfig(p)
 local delta={};for k,v in pairs(p) do if cfg[k]~=v then cfg[k]=v;delta[k]=v end end
 if next(delta) then changed:Fire(delta) end;return true
end
''' + module('extras/universal/fly.luau') + '''
assert(mod.setup({Utils=u}))
local co=coroutine.create(function() mod.setEnabled(true) end)
assert(coroutine.resume(co));assert(coroutine.status(co)=='suspended')
mod.teardown()
local ok,err=coroutine.resume(co);assert(ok,err)
for _,object in ipairs(objects) do assert(not object.Parent,'flight object survived teardown') end
assert(not humanoid.PlatformStand and humanoid.AutoRotate)
''')

    def test_character_rebinds_after_root_replacement(self):
        run_case(COMMON + '''
local root=instance('BasePart');root.Name='HumanoidRootPart'
local character=instance('Model');character.AncestryChanged=signal();character.ChildAdded=signal();character.ChildRemoved=signal()
character.FindFirstChild=function() return root end;character.FindFirstChildOfClass=function() end
local player={Character=character,CharacterAdded=signal(),CharacterRemoving=signal()}
task={spawn=function(fn) fn() end,delay=function() end,wait=function() root=instance('BasePart');root.Name='HumanoidRootPart' end}
local u={getLocalPlayer=function() return player end,isActive=function() return true end}
for _,k in ipairs({'trackGlobal','untrackGlobal','trackCharacter','disconnectCharacterConnections','setManualSpamActive','setAutoSpamActive','recordTransition','recordError'}) do u[k]=function() end end
local binds,detaches=0,0
''' + module('aux/character.luau') + '''
assert(mod.setup({Utils=u,Spam={resetState=function() end},characterBinds={{name='test',
 bind=function() binds=binds+1;return true end,detach=function() detaches=detaches+1 end}}}))
assert(binds==1)
local previous=root;root=nil;character.ChildRemoved:Fire(previous)
assert(binds==2 and detaches==1,'root replacement left modules bound to obsolete root')
mod.teardown()
''')


if __name__ == '__main__':
    unittest.main()
