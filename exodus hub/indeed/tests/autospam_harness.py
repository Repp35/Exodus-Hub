"""Real AutoSpam + real Spam scheduler, with explicit engine/transport doubles."""
from test_logic_reliability import COMMON, module, run_case

ENGINE = '''
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
local heart, spamChanged, configChanged = signal(), signal(), signal()
function heart:Wait() coroutine.yield() end
local threads={}; task={wait=function() coroutine.yield() end,delay=function() end,defer=function(fn) fn() end}
function task.spawn(fn) local co=coroutine.create(fn);threads[#threads+1]=co;local ok,e=coroutine.resume(co);assert(ok,e);return co end
local function person(id,x)
 local root=instance('BasePart');root.Position=v(x);root.AssemblyLinearVelocity=v()
 local animator=instance('Animator');animator.AnimationPlayed=signal();animator.active={}
 function animator:GetPlayingAnimationTracks() local t={} for track in pairs(self.active) do if track.IsPlaying then t[#t+1]=track end end return t end
 local hum=instance('Humanoid',{Animator=animator});hum.Health=100;hum.Died=signal();hum.ChildAdded=signal()
 function hum:FindFirstChildOfClass(kind) return kind=='Animator' and animator or nil end
 local char=instance('Model',{HumanoidRootPart=root,Humanoid=hum})
 char.AncestryChanged=signal();char.ChildAdded=signal();function char:FindFirstChildOfClass(kind) return kind=='Humanoid' and hum or nil end
 local p={UserId=id,Character=char,CharacterAdded=signal(),root=root,hum=hum,animator=animator,attrs={Lives=3,Playing=true},signals={}}
 function p:GetAttribute(key) return self.attrs[key] end
 function p:GetAttributeChangedSignal(key) if not self.signals[key] then self.signals[key]=signal() end return self.signals[key] end
 return p
end
local me,other,third=person(42,0),person(99,10),person(88,80)
local people={[42]=me,[99]=other,[88]=third}
local players={PlayerAdded=signal(),PlayerRemoving=signal(),LocalPlayer=me}
function players:GetPlayerByUserId(id) return people[id] end
function players:GetPlayers() return {me,other,third} end
local ball=instance('BasePart')
local snap={ball=ball,position=v(50),velocity=v(-600),speed=600,syncSpeed=600,targetId=42,targeted=true,syncAt=tm,syncSequence=1}
local cd={blocking=false,miss=false,source='local'}
local cfg={AutoSpam=true,SpamRateMode='CPS',CPS=24};local enabled,manual,auto=true,false,false
local wall,frozen=false,false;local dashSamples={};local clicks=0;local transitions={}
local world={attrs={MatchStatus=6},changed=signal()}
function world:GetAttribute(key) return self.attrs[key] end
function world:GetAttributeChangedSignal() return self.changed end
function world:Raycast() return wall and {} or nil end
local tracked={};local animationCatalog={['101']='start',['102']='loop',['103']='parry'}
local u={now=function() return tm end,getLocalPlayer=function() return me end,getPlayers=function() return players end,
 getRunService=function() return {Heartbeat=heart} end,getWorkspace=function() return world end,
 isActive=function() return enabled end,getConfigValue=function(k) return cfg[k] end,
 isManualSpamActive=function() return manual end,isAutoSpamActive=function() return auto end,isDynamicSpamActive=function() return false end,
 setManualSpamActive=function(x) manual=x;spamChanged:Fire() end,setAutoSpamActive=function(x) auto=x;spamChanged:Fire() end,
 observeSpam=function(fn) return spamChanged:Connect(fn) end,observeConfig=function(fn) return configChanged:Connect(fn) end,
 trackGlobal=function() end,untrackGlobal=function() end,trackCharacter=function(c) tracked[c]=true end,untrackCharacter=function(c) tracked[c]=nil end,
 apiVersion=function() return 1 end,recordTransition=function(...) transitions[#transitions+1]={...} end,recordError=function(_,err) error(err) end}
local geometryFactors={}
local g={getDeflectAnimationCatalog=function() return animationCatalog end,getDeflectTargetPrediction=function() return nil end,getSnapshotAt=function() return snap end,isSnapshotValid=function(s) return s and s.ball and s.ball.Parent~=nil end,
 getPlayerMotion=function(id) local p=people[id];return p and p.root.Position,p and p.root.AssemblyLinearVelocity end,
 getAveragePing=function() return 0 end,getBallSpeedLimits=function() return 16,600 end,
 getPlayerRawRadius=function() return 8.5 end,getDeflectWindow=function(speed) return .85-.65*math.clamp((speed-16)/584,0,1) end,getDeflectGeometry=function(speed,_,factor)
  geometryFactors[#geometryFactors+1]=factor
  local window=.85-.65*math.clamp((speed-16)/584,0,1)
  return {noWindowParryRadius=8.5,fullRadius=8.5+speed*window*factor,effectiveWindow=window*factor,leadTime=window*factor,deflectWindow=window} end,
 getBallFrozen=function() return frozen end,getLocalDashState=function() return false,120,.2 end,
 getHaunterEvent=function() end,areAbilitiesEnabled=function() return true end,getTargetId=function() return snap.targetId end,
 getClashContext=function() end,getDefensePhysics=function() return {killRadius=4} end,
 getAutoSpamDelay=function() return 0 end,getMinimumSpamInterval=function() return .0301 end}
local c={getDeflectCooldownState=function() return cd end}
local defense={enabled=true,responseBudget=1/4.73}
local defender={getPressureDetector=function() return defense end}
local stats
local st={begin=function(id,t) stats={partnerId=id,startedAt=t,frozen=false} end,get=function() return stats end,
 getStatus=function() return stats or {} end,observe=function() end,finish=function() if stats then stats.frozen=true end end,freeze=function() if stats then stats.frozen=true end end,waitForNextClash=function() end}
local d={tick=function() end,getEstimate=function(id) return dashSamples[id] end}
RaycastParams={new=function() return {} end}; Enum={RaycastFilterType={Exclude=1}}
local r={fireParry=function(_,guard) if not guard() then return false,'Deflect cancelado' end clicks=clicks+1;return true end}
'''
API = '''
assert(ap.setup({Utils=u,GameInfo=g,Cooldown=c,ClashStats=st,Dash=d,AutoParry=defender}))
assert(ap.bindCharacter(me.Character))
assert(spam.setup({Utils=u,GameInfo=g,AutoSpam=ap,Remote=r,DynamicParry={canSend=function() return false end}}))
local function advance(dt)
 tm=tm+dt
 for _,co in ipairs(table.clone(threads)) do if coroutine.status(co)=='suspended' then local ok,e=coroutine.resume(co);assert(ok,e) end end
end
local function heartbeat(dt) advance(dt or .016);snap.syncAt=tm;heart:Fire(dt or .016) end
local function packet(target,dt,pos,seq)
 advance(dt or 0);snap.targetId=target;snap.targeted=target==42;snap.syncAt=tm
 snap.syncSequence=seq or (snap.syncSequence+1)%65536
 if pos then snap.position=v(pos) end
 ap.onBallSync({Source='packet',Sequence=snap.syncSequence,TargetPlayerID=target,Speed=snap.syncSpeed})
end
local function dash(id,velocity)
 local p=people[id];dashSamples[id]={ability="normal",signalActive=true,observedAt=tm,position=p.root.Position,velocity=v(velocity),normalModel={estimatedRemaining=.2}}
end
local function animate(id,phase,position,rate,emit)
 local p=people[id];local track={Animation={AnimationId='rbxassetid://'..tostring(phase)},IsPlaying=true,TimePosition=position or 0,Speed=rate or 1}
 p.animator.active[track]=true
 if emit~=false then p.animator.AnimationPlayed:Fire(track) end
 return track
end
local function stopped(reason) assert(not ap.isActive(),reason);assert(ap.getStatus().lastStopReason==reason,ap.getStatus().lastStopReason) end
'''
def check(case, extra=""):
    run_case(COMMON + ENGINE + module('autospam.luau').replace('local mod=', 'local ap=', 1) + module('spam.luau').replace('local mod=', 'local spam=', 1) + API + extra + case)
