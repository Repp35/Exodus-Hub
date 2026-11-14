-- Deterministic Roblox doubles for visibility/lifecycle tests. No renderer/FPS claim.
local os = setmetatable({}, { __index = os })
local math = setmetatable({}, { __index = math })
local table = setmetatable({}, { __index = table })
local clock = 0
os.clock = function() return clock end
local function advance(dt) clock = clock + (dt or 0.1) end
local tasks = {}
task = {}
function task.defer(fn) tasks[#tasks + 1] = fn end
function task.delay(_, fn) tasks[#tasks + 1] = fn end
function task.spawn(fn) tasks[#tasks + 1] = fn end
local function flush()
  local turns = 0
  while #tasks > 0 do
    local batch = tasks; tasks = {}
    for _, fn in ipairs(batch) do fn() end
    turns = turns + 1
    assert(turns < 1000, "worker did not become idle")
  end
end
function warn() end
function table.clear(t) for key in pairs(t) do t[key] = nil end end
function table.clone(t) local result = {}; for key, value in pairs(t) do result[key] = value end; return result end
function math.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local liveConnections = 0
local function signal()
  local s = { list = {} }
  function s:Connect(fn)
    local c = { Connected = true, Enabled = true, Function = fn }
    function c:Disconnect() if self.Connected then self.Connected = false; liveConnections = liveConnections - 1 end end
    function c:Disable() self.Enabled = false end
    function c:Enable() self.Enabled = true end
    self.list[#self.list + 1] = c; liveConnections = liveConnections + 1
    return c
  end
  function s:Fire(...)
    local batch = table.clone(self.list)
    for _, c in ipairs(batch) do if c.Connected and c.Enabled then c.Function(...) end end
  end
  function s:Wait() end
  return s
end
local V = {}
V.__index = function(v, key)
  if key == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
  return V[key]
end
local function vec(x,y,z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
V.__add = function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
V.__sub = function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
V.__unm = function(a) return vec(-a.X,-a.Y,-a.Z) end
V.__mul = function(a,b) if type(a)=="number" then a,b=b,a end; return vec(a.X*b,a.Y*b,a.Z*b) end
V.__div = function(a,b) return a * (1/b) end
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
Vector3 = { new = vec, zero = vec() }
local CF = {}; CF.__index = CF
local function frame(position, yaw)
  yaw = yaw or 0
  return setmetatable({ Position=position or vec(), yaw=yaw,
    RightVector=vec(math.cos(yaw),0,-math.sin(yaw)), UpVector=vec(0,1,0), LookVector=vec(-math.sin(yaw),0,-math.cos(yaw)) }, CF)
end
function CF:PointToObjectSpace(p)
  local d = p-self.Position
  return vec(d:Dot(self.RightVector),d:Dot(self.UpVector),-d:Dot(self.LookVector))
end
function CF:PointToWorldSpace(p) return self.Position+self.RightVector*p.X+self.UpVector*p.Y-self.LookVector*p.Z end
function CF:ToObjectSpace(other) return frame(self:PointToObjectSpace(other.Position),other.yaw-self.yaw) end
CF.__mul = function(a,b) return frame(a:PointToWorldSpace(b.Position),a.yaw+b.yaw) end
CFrame = { new = function(x,y,z) return frame(type(x)=="table" and x or vec(x,y,z)) end }
CFrame.identity = CFrame.new()
NumberSequence={new=function(v) return v end}
NumberRange={new=function(v) return v end}
Color3={new=function(r,g,b) return vec(r,g,b) end,fromRGB=function(r,g,b) return vec(r/255,g/255,b/255) end}
Enum=setmetatable({}, {__index=function(t,k) local v=setmetatable({}, {__index=function(a,b) rawset(a,b,k.."."..b);return a[b] end});rawset(t,k,v);return v end})
RaycastParams={new=function() return {} end}
Region3={new=function(a,b) return {min=a,max=b} end}
local objects={}
local stats={getPlayers=0,getDescendants=0,bounds=0}
local methods={}
local objectMeta={}
objectMeta.__index=function(o,k)
  if methods[k] then return methods[k] end
  if k=="Position" then return o.props.CFrame.Position end
  return o.props[k]
end
objectMeta.__newindex=function(o,k,v)
  local previous=o.props[k]
  o.props[k]=v
  if previous~=v and o.props.Changed then
    o.props.Changed:Fire(k)
    if o.props.propertySignals[k] then o.props.propertySignals[k]:Fire() end
  end
end
local function node(class,name,parent,position,size)
  local o=setmetatable({props={ClassName=class,Name=name,Parent=parent,Anchored=true,Transparency=0,
    LocalTransparencyModifier=0,Size=size or vec(4,4,4),CFrame=frame(position),Shape=Enum.PartType.Block,
    Enabled=true,CanCollide=true,CanQuery=true,CanTouch=true,CastShadow=true,Material="original",Reflectance=0.3,TextureID="original-texture",
    Changed=signal(),DescendantAdded=signal(),DescendantRemoving=signal(),AttributeChanged=signal(),attributes={},attributeSignals={},propertySignals={}}},objectMeta)
  objects[#objects+1]=o
  return o
end
function typeof(o) if getmetatable(o)==objectMeta then return "Instance" end; return type(o) end
function methods:IsA(class)
  return self.ClassName==class or class=="BasePart" and (self.ClassName=="Part" or self.ClassName=="MeshPart")
    or class=="Light" and self.ClassName=="PointLight"
end
function methods:IsDescendantOf(root)
  local parent=self.Parent
  while parent do if parent==root then return true end; parent=parent.Parent end
  return false
end
function methods:GetChildren()
  local result={}
  for _,o in ipairs(objects) do if o.Parent==self then result[#result+1]=o end end
  return result
end
function methods:GetDescendants()
  stats.getDescendants=stats.getDescendants+1
  local result={}
  for _,o in ipairs(objects) do if o:IsDescendantOf(self) then result[#result+1]=o end end
  return result
end
function methods:FindFirstChild(name)
  for _,o in ipairs(self:GetChildren()) do if o.Name==name then return o end end
end
function methods:FindFirstChildOfClass(class)
  for _,o in ipairs(self:GetChildren()) do if o:IsA(class) then return o end end
end
function methods:GetPropertyChangedSignal(key)
  if not self.props.propertySignals[key] then self.props.propertySignals[key]=signal() end
  return self.props.propertySignals[key]
end
function methods:GetAttribute(key) return self.props.attributes[key] end
function methods:GetAttributeChangedSignal(key)
  if not self.props.attributeSignals[key] then self.props.attributeSignals[key]=signal() end
  return self.props.attributeSignals[key]
end
function methods:SetAttribute(key,value)
  if self.props.attributes[key]~=value then
    self.props.attributes[key]=value
    self:GetAttributeChangedSignal(key):Fire();self.AttributeChanged:Fire(key)
  end
end
function methods:GetBoundingBox()
  stats.bounds=stats.bounds+1
  local root=self:FindFirstChild("HumanoidRootPart")
  return root and root.CFrame or self.CFrame,vec(8,12,8)
end
local function reparent(o,parent)
  local subtree={o}
  for _,child in ipairs(o:GetDescendants()) do subtree[#subtree+1]=child end
  local old=o.Parent
  while old do
    for _,child in ipairs(subtree) do old.DescendantRemoving:Fire(child) end
    old=old.Parent
  end
  o.Parent=parent
  while parent do
    for _,child in ipairs(subtree) do parent.DescendantAdded:Fire(child) end
    parent=parent.Parent
  end
end
local workspace=node("Workspace","Workspace")
local lighting=node("Lighting","Lighting")
local player=node("Player","LocalPlayer")
player.UserId=1
local runService={Heartbeat=signal(),RenderStepped=signal()}
local players={LocalPlayer=player,PlayerAdded=signal(),PlayerRemoving=signal(),roster={player}}
function players:GetPlayers() stats.getPlayers=stats.getPlayers+1;return table.clone(self.roster) end
local camera={CFrame=frame(),FieldOfView=70,ViewportSize={X=1600,Y=900}}
workspace.CurrentCamera=camera
workspace.Raycast=function() return nil end
local collection={HasTag=function() return false end,GetInstanceAddedSignal=function() return signal() end,GetInstanceRemovedSignal=function() return signal() end}
local options={CullDistance=160,CullBudgetMs=0.65,CullInterval=0.05,CullOcclusion=true,HideLobbyInMatch=true,GameNoVFX=true,GameReducedUI=true,GameReducedHeadLook=true}
local function getOption(k) return options[k] end
local masks={}
local function onHidden(o,value) masks[o]=value or nil end
local function addRemote(id,pos)
  local p=node("Player","Remote"..id);p.UserId=id;p.CharacterAdded=signal();p.CharacterRemoving=signal()
  p.Character=node("Model","Character"..id,workspace)
  node("Humanoid","Humanoid",p.Character)
  node("Part","HumanoidRootPart",p.Character,pos or vec(0,0,-50))
  node("Part","Head",p.Character,pos or vec(0,0,-50))
  players.roster[#players.roster+1]=p;players.PlayerAdded:Fire(p)
  return p
end
player.CharacterAdded=signal();player.CharacterRemoving=signal()
