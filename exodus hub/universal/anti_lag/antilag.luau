-- [[ shared, reversible scene optimization ]]
--!optimize 2
-- @modules antilag
local AntiLag = {}
local utils, properties, spatial, lifetime, scheduler
local session, observer
local working, revision = false, 0
local CONFIG = {
  schema = {
    AntiLagEnabled = "boolean",
    AntiLagDistanceCull = "boolean",
    AntiLagRenderDistance = "rate",
    AntiLagKeepNear = "rate",
    AntiLagSimplifyFar = "boolean",
    AntiLagRemoveEffects = "boolean",
    AntiLagRemoveTextures = "boolean",
    AntiLagFlatMaterials = "boolean",
    AntiLagLowestGraphics = "boolean",
  },
  defaults = {
    AntiLagEnabled = false,
    AntiLagDistanceCull = true,
    AntiLagRenderDistance = 1200,
    AntiLagKeepNear = 128,
    AntiLagSimplifyFar = true,
    AntiLagRemoveEffects = true,
    AntiLagRemoveTextures = false,
    AntiLagFlatMaterials = false,
    AntiLagLowestGraphics = true,
  },
  constraints = { AntiLagRenderDistance = { min = 300, max = 6000 }, AntiLagKeepNear = { min = 64, max = 512 } },
}
local function setting(key)
  local value = utils and utils.getConfigValue(key)
  return if value == nil then CONFIG.defaults[key] else value
end
local function profile()
  return {
    StartEnabled = false,
    CullEnabled = setting("AntiLagDistanceCull"),
    CullDistance = math.max(setting("AntiLagRenderDistance"), setting("AntiLagKeepNear") * 2),
    CullKeepNear = setting("AntiLagKeepNear"),
    SimplifyFar = setting("AntiLagSimplifyFar"),
    Particles = setting("AntiLagRemoveEffects"),
    TrailsAndBeams = setting("AntiLagRemoveEffects"),
    LegacyEffects = setting("AntiLagRemoveEffects"),
    RemoveTextures = setting("AntiLagRemoveTextures"),
    FlatMaterials = setting("AntiLagFlatMaterials"),
    LowestGraphics = setting("AntiLagLowestGraphics"),
    PostEffects = true,
    Lights = true,
    Shadows = true,
    FlatLighting = true,
    FlatSky = true,
    Atmosphere = true,
    Clouds = true,
    NoFog = true,
    Water = true,
    TransparentWater = false,
    TerrainDecoration = true,
    MaintainEffects = true,
    RestoreLatest = false,
    FlatSkyTexture = "",
    BudgetMs = 0.4,
    MaxItemsPerFrame = 32,
    ReapplyInterval = 0.5,
  }
end
local function stop()
  local owner = session
  if not owner then
    return
  end
  if owner.spatial then
    owner.spatial:Destroy()
  end
  if owner.engine then
    owner.engine:Destroy()
    while owner.engine:GetStatus().Alive do
      game:GetService("RunService").Heartbeat:Wait()
    end
  end
  owner.scope.destroy()
  if session == owner then
    session = nil
  end
end
local function start()
  local settings
  pcall(function() settings = UserSettings():GetService("UserGameSettings") end)
  local owner = { scope = lifetime.scope(), detail = setmetatable({}, { __mode = "k" }), profile = profile() }
  session = owner
  owner.engine = properties.create({
    Workspace = workspace,
    Lighting = game:GetService("Lighting"),
    RunService = game:GetService("RunService"),
    CollectionService = game:GetService("CollectionService"),
    GameSettings = settings,
    Roots = { workspace, game:GetService("Lighting") },
    PhasesPerFrame = 2,
    ConnectPhysics = function(callback)
      local scope = owner.scope.child()
      scheduler.connectPhysics(scope, callback)
      return { Disconnect = scope.destroy }
    end,
    ExtraPolicy = function(object, target, watch)
      local state = owner.detail[object]
      if state == "hidden" then
        target.LocalTransparencyModifier = 1
      elseif state == "simple" then
        target.Reflectance = 0
        if object:IsA("MeshPart") then
          target.RenderFidelity = Enum.RenderFidelity.Performance
        end
      end
      return target, watch
    end,
  }, owner.profile)
  owner.spatial = spatial.create({
    Workspace = workspace,
    ConnectPhysics = function(callback)
      local scope = owner.scope.child()
      scheduler.connectPhysics(scope, callback)
      return { Disconnect = scope.destroy }
    end,
    GetFocusPosition = function()
      local player = utils.getLocalPlayer()
      local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
      return root and root.Position
    end,
    OnState = function(object, state)
      owner.detail[object] = state
      owner.engine:RefreshInstance(object, false)
    end,
  }, function(key) return owner.engine:GetOption(key) end)
  owner.engine:SetEnabled(true)
  owner.spatial:SetEnabled(owner.profile.CullEnabled or owner.profile.SimplifyFar)
end
local function reconcile()
  revision += 1
  if working then
    return
  end
  working = true
  task.defer(function()
    local seen
    repeat
      seen = revision
      local ok, reason = pcall(function()
        if utils and utils.isActive() and setting("AntiLagEnabled") then
          if not session then
            start()
          else
            local requested = profile()
            session.engine:SetOptions(requested)
            session.profile = requested
            session.spatial:SetEnabled(requested.CullEnabled or requested.SimplifyFar)
            session.spatial:Refresh()
          end
        else
          stop()
        end
      end)
      if not ok then
        local reporting = utils
        local restored, restoreError = pcall(stop)
        if reporting then
          reporting.recordError("AntiLag", tostring(reason))
          reporting.setConfig({ AntiLagEnabled = false })
        end
        if not restored then
          warn("[Exodus AntiLag] " .. tostring(restoreError))
        end
      end
    until seen == revision
    working = false
  end)
end
function AntiLag.setEnabled(enabled)
  if not utils then
    return false, "recurso indisponível"
  end
  return utils.setConfig({ AntiLagEnabled = enabled == true })
end
function AntiLag.getStatus()
  return {
    enabled = session ~= nil,
    busy = working,
    engine = session and session.engine and session.engine:GetStatus(),
    spatial = session and session.spatial and session.spatial:GetStatus(),
  }
end
function AntiLag.teardown()
  utils = nil
  revision += 1
  if observer then
    observer:Disconnect()
    observer = nil
  end
  while working do
    game:GetService("RunService").Heartbeat:Wait()
  end
  stop()
  return true
end
function AntiLag.setup(deps)
  AntiLag.teardown()
  utils, properties, spatial, lifetime, scheduler = deps.Utils, deps.Properties, deps.Spatial, deps.Lifetime, deps.Controller
  observer = utils.observeConfig(function(changes)
    for key in pairs(changes) do
      if CONFIG.schema[key] and (session or setting("AntiLagEnabled")) then
        reconcile()
        break
      end
    end
  end)
  if setting("AntiLagEnabled") then
    reconcile()
  end
  return true
end
AntiLag.__config = CONFIG
AntiLag.__contract = {
  provides = { "setup", "teardown", "setEnabled", "getStatus" },
  requires = { Utils = "utils", Lifetime = "lifetime", Controller = "universalcontroller", Properties = "renderproperties", Spatial = "renderspatial" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "getLocalPlayer", "isActive", "observeConfig", "recordError" },
    Lifetime = { "scope" },
    Controller = { "connectPhysics" },
    Properties = { "create" },
    Spatial = { "create" },
  },
}
return AntiLag
