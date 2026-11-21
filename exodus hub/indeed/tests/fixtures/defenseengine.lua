
math.clamp=function(v,a,b) return math.max(a,math.min(b,v)) end
table.clear=function(t) for k in pairs(t) do t[k]=nil end end
function typeof(v) return type(v)=='table' and (v._type or 'table') or type(v) end
local clock=10;os.clock=function() return clock end
local logs={};function warn(s) logs[#logs+1]=s end
function signal()
 local s={handlers={}}
 function s:Connect(fn) local c={Connected=true};function c:Disconnect() self.Connected=false end;s.handlers[#s.handlers+1]={fn=fn,c=c};return c end
 function s:Fire(...) for _,e in ipairs(self.handlers) do if e.c.Connected then e.fn(...) end end end
 return s
end
local vm={}
function vec(x,y,z) return setmetatable({_type='Vector3',X=x,Y=y or 0,Z=z or 0},vm) end
vm.__add=function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vm.__sub=function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vm.__mul=function(a,b) if type(a)=='number' then a,b=b,a end;return vec(a.X*b,a.Y*b,a.Z*b) end
vm.__div=function(a,b) return a*(1/b) end
vm.__index=function(a,k)
 if k=='Magnitude' then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
 if k=='Unit' then return a/a.Magnitude end
 if k=='Dot' then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
end
Vector3={zero=vec(0),new=vec}
Color3={fromRGB=function(r,g,b) return {_type='Color3',R=r/255,G=g/255,B=b/255} end}
function sequence(color) return {_type='ColorSequence',Keypoints={{Time=0,Value=color},{Time=1,Value=color}}} end
local red=Color3.fromRGB(202,56,30);local gray=Color3.fromRGB(153,153,153)
Vector2={new=function(x,y) return {X=x,Y=y} end}
UDim2={new=function(a,b,c,d) return {X={Scale=a,Offset=b},Y={Scale=c,Offset=d}} end,fromOffset=function(x,y) return {X={Offset=x},Y={Offset=y}} end}
UDim={new=function(a,b) return {Scale=a,Offset=b} end}
Enum={Font={GothamSemibold=1},TextXAlignment={Left=1},TextYAlignment={Top=1},ZIndexBehavior={Global=1}}
local created={}
function node(name,cls)
 local n={_type='Instance',Name=name,ClassName=cls or 'Folder',Parent=true,children={},attrs={},changes={},properties={}}
 function n:IsA(c) return c==self.ClassName end
 function n:FindFirstChild(k,recursive)
  if recursive then self.deepFinds=(self.deepFinds or 0)+1 end
  if self.children[k] then return self.children[k] end
  if recursive then for _,v in pairs(self.children) do local r=v:FindFirstChild(k,true);if r then return r end end end
 end
 function n:FindFirstChildOfClass(c) for _,v in pairs(self.children) do if v:IsA(c) then return v end end end
 function n:WaitForChild(k) return assert(self:FindFirstChild(k),k) end
 function n:GetAttribute(k) return self.attrs[k] end
 function n:GetAttributeChangedSignal(k) if not self.changes[k] then self.changes[k]=signal() end;return self.changes[k] end
 function n:SetAttribute(k,v) if self.attrs[k]~=v then self.attrs[k]=v;self:GetAttributeChangedSignal(k):Fire() end end
 function n:GetPropertyChangedSignal(k) if not self.properties[k] then self.properties[k]=signal() end;return self.properties[k] end
 function n:Destroy() self.Parent=nil end
 return n
end
function add(p,n) p.children[n.Name]=n;n.Parent=p;return n end
function module(p,n,value) local m=add(p,node(n,'ModuleScript'));m.value=value;return m end
function part(name,x)
 local p=node(name,'BasePart');p.Position=vec(x or 8);p.AssemblyLinearVelocity=vec(-16);p.Color=gray;p.Transparency=0;p.LocalTransparencyModifier=0;return p
end
Instance={new=function(cls) local n=node(cls,cls);created[cls]=n;return n end}
require=function(m) if m.fail then error(m.fail) end;return m.value end
local env={};getgenv=function() return env end
local S
local function setup()
 if env.ExodusAutoParryLabStop then env.ExodusAutoParryLabStop() end
 clock=clock+2
 local world=node('Workspace');workspace=world
 function world:GetServerTimeNow() return clock end
 world.DescendantAdded=signal();world.DescendantRemoving=signal();world.attrs.MatchStatus=1
 local rs=node('ReplicatedStorage');local shared=add(rs,node('Shared'));local gameplay=add(shared,node('Gameplay'))
 local runs={PreSimulation=signal(),PostSimulation=signal(),RenderStepped=signal(),Heartbeat=signal()}
 local player=node('Player','Player');player.UserId=123;player.attrs.Lives=3;player.attrs.DeflectRange=8.5
 player.CharacterAdded=signal();player.CharacterRemoving=signal();player.ping=0.02;player.pingReads=0
 function player:GetNetworkPing() self.pingReads=self.pingReads+1;return self.ping end
 add(player,node('PlayerGui','PlayerGui'))
 local char=add(world,node('Character','Model'));local root=add(char,part('HumanoidRootPart',0));root.AssemblyLinearVelocity=vec(0)
 local hum=add(char,node('Humanoid','Humanoid'));hum.Health=100;player.Character=char
 local mark=add(rs,node('PlayerBallHighlight','Highlight'));mark.Enabled=false
 local ball=add(world,part('GameBall',8))
 local input={focus=false};function input:GetFocusedTextBox() return self.focus end
 local native={syncData={TargetPlayerID=456,Speed=16},history={},latestTargetId=456,lastSeq=0,calls=0,simulationCalls=0}
 function native:ApplySnapshot(p)
  self.syncData={TargetPlayerID=p.targetId,HighlightTargetPlayerID=p.highlightId,Speed=p.speed,Locked=p.locked}
  self.latestTargetId=p.targetId;self.history[#self.history+1]=p;self.lastSeq=p.seq
 end
 function native:IsLocalTarget() return self.latestTargetId==123 end
 function native:SimulateFrom(p,age,own)
  self.simulationCalls=self.simulationCalls+1
  return p.position+(p.velocity or vec(-p.speed))*age
 end
 local rm=module(gameplay,'BallReplicator',{BallReplicator=native})
 local hit=signal();module(rm,'BallFeel',{Hit=hit})
 local gb={};function gb:GetBaseSpeed() return 16 end;function gb:GetMaxSpeed() return 600 end
 function gb:IsInClash() return self.clash==true end
 function gb:GetClashMinWindow() return 0.32 end
 function gb:ApplyClashPressure(w) return w+(0.03-w)*(self.pressure or 0) end
 module(gameplay,'GameBall',{GameBall=gb})
 local ca={Abilities={}};local ability={LastDeflectCallAt=nil,ClickInstances={},calls=0,alive=true}
 function ability:IsOwnerAlive() return self.alive end
 function ability:Deflect()
  if input.focus then return end
  local now=os.clock()
  if now-(self.LastDeflectCallAt or -math.huge)<0.008 then return end
  self.LastDeflectCallAt=now
  if not self.alive then return end
  self.calls=self.calls+1
 end
 ca.Abilities[1]=ability;module(add(shared,node('Abilities')),'ClientAbilities',ca)
 local gd={GetFallback=function(_,owner,key,fallback) native.dataReads=(native.dataReads or 0)+1; local v=owner:GetAttribute(key);if v==nil then return fallback end;return v end}
 module(add(shared,node('Core')),'GameData',{GameData=gd})
 module(add(shared,node('Enums')),'MatchStatus',{MatchStatus={InGame=1}})
 local trainingRS=add(rs,node('Training'));local tr=add(trainingRS,node('Remotes'))
 local block=add(tr,node('Block','RemoteEvent'));block.calls=0
 function block:FireServer(pos,dir) assert(typeof(pos)=='Vector3' and typeof(dir)=='Vector3');self.calls=self.calls+1 end
 local ballState=add(tr,node('BallState','UnreliableRemoteEvent'));ballState.OnClientEvent=signal()
 local event=add(tr,node('Event','RemoteEvent'));event.OnClientEvent=signal()
 local ts={inZone=false,DefaultCpsLimit=16};ts.InZone=function() return ts.inZone end
 ts.GetBlockWindow=function(speed) return 0.85+(0.2-0.85)*math.clamp((speed-16)/(600-16),0,1) end
 module(trainingRS,'TrainingShared',ts)
 local trainingWorld=add(world,node('Training'));local tc=add(trainingWorld,node('TrainingClient'))
 local tb=add(tc,part('TrainingBall',8));local trails=add(tb,node('Trails'))
 local trail=add(trails,node('BallTrail','Trail'));trail.Enabled=true;trail.Color=sequence(gray)
 local targetTrail=add(trails,node('BallTrailTarget','Trail'));targetTrail.Color=sequence(red)
 local normalTrail=add(trails,node('BallTrail2','Trail'));normalTrail.Color=sequence(gray)
 world.CurrentCamera={CFrame={Position=vec(0),LookVector=vec(1)}}
 local services={Players={LocalPlayer=player},ReplicatedStorage=rs,RunService=runs,UserInputService=input,TextService={GetTextSize=function(_,text) return {X=#text*7,Y=16} end}}
 game={GetService=function(_,k) return assert(services[k],k) end}
 S={world=world,rs=rs,player=player,root=root,hum=hum,char=char,mark=mark,ball=ball,runs=runs,input=input,native=native,ability=ability,ca=ca,training=ts,trainingBall=tb,trail=trail,targetTrail=targetTrail,normalTrail=normalTrail,block=block,ballState=ballState,event=event,seq=0,hit=hit,gb=gb}
 return S
end
local checks=0
local function check(v,msg) assert(v,msg);checks=checks+1 end
local function matchPacket(target,options)
 options=options or {};clock=clock+(options.dt or 0.02);S.seq=(S.seq+1)%65536
 local speed=options.speed or 16
 local p={targetId=target,highlightId=options.highlightId,seq=options.seq or S.seq,speed=speed,serverTime=clock-(options.age or 0.02),position=options.position or vec((options.distance or 8)+speed*0.02),velocity=options.velocity}
 S.native:ApplySnapshot(p);return p
end
local function trainPacket(goal,options)
 options=options or {};clock=clock+(options.dt or 0.02);local speed=options.speed or 16
 S.ballState.OnClientEvent:Fire(options.position or vec(8+speed*0.02),options.velocity or vec(-speed),options.time or clock-(options.age or 0.02),goal,options.targetId or 77,speed)
end
local function render(dt) clock=clock+(dt or 1/60);S.runs.RenderStepped:Fire() end
local function heartbeat(dt) clock=clock+(dt or 0.01);S.runs.Heartbeat:Fire(dt or 0.01) end
local function attribute(target,dt) clock=clock+(dt or 0.001);S.world:SetAttribute('GameBallTarget',target) end
local function trainingMode() S.training.inZone=true;S.player:SetAttribute('Lives',0);heartbeat() end
