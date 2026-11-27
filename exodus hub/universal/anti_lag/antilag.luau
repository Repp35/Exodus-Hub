-- [[ antilag ]]
--!optimize 2
-- @modules renderadapter, antilag

-- code
local __part_renderadapter = (function()
  local Adapter = {}
  local hub
  function Adapter.setup(deps)
    hub = deps.Hub
    return true
  end
  function Adapter.isAvailable() return hub.isNativeVisualAvailable() end
  function Adapter.create(...) return hub.createVisualAdapter(...) end
  function Adapter.apply(...) return hub.applyVisualPolicy(...) end
  Adapter.__contract = {
    access = { default = "render.write" },
    provides = { "setup", "create", "apply", "isAvailable" },
    requires = { Hub = "hubapi" },
    requiresMethods = { Hub = { "createVisualAdapter", "applyVisualPolicy", "isNativeVisualAvailable" } },
  }
  return Adapter
end)()
local __part_antilag = (function()
  local AntiLag = {}
  local Utils
  local properties
  local adapter
  local spatial
  local lifetime, scheduler
  local CONFIG = {
    schema = {
      AntiLagEnabled = "boolean",
      AntiLagFloorCull = "boolean",
      AntiLagRenderDistance = "rate",
      AntiLagRemoveSwordSounds = "boolean",
      AntiLagRemoveEffects = "boolean",
    },
    defaults = {
      AntiLagEnabled = false,
      AntiLagFloorCull = true,
      AntiLagRenderDistance = 300,
      AntiLagRemoveSwordSounds = true,
      AntiLagRemoveEffects = true,
    },
  }

  local PROFILE = {
    StartEnabled = false,
    ShowMenu = false,
    CullEnabled = true,
    CullView = false,
    CullVertical = false,
    CullAbove = 200,
    CullBelow = 100,
    CullVerticalMargin = 20,
    CullFloorEnabled = true,
    GameSwordSounds = false,
    CullDistance = 300,
    CullKeepNear = 16,
    CullViewPadding = 12,
    CullViewDegrees = 8,
    CullHideDelay = 0.15,
    CullInterval = 0.1,
    CullBudgetMs = 0.8,
    GameGenerators = true,
    GameNoVFX = true,
    GameKeepIndicators = true,
    GameCosmeticAudio = true,
    GameKeepCombatAudio = true,
    GameMuteMusic = true,
    GameMuteAmbience = true,
    GameReducedUI = true,
    GameReducedHeadLook = true,
    Particles = true,
    TrailsAndBeams = true,
    LegacyEffects = true,
    PostEffects = true,
    Lights = true,
    Shadows = true,
    FlatLighting = true,
    FlatSky = true,
    Atmosphere = true,
    Clouds = true,
    NoFog = false,
    Water = true,
    TransparentWater = true,
    TerrainDecoration = true,
    FlatMaterials = false,
    HideTaggedDecorations = false,
    LowestGraphics = false,
    MaintainEffects = true,
    RestoreLatest = false,
    ShowFPS = false,
    FlatSkyTexture = "",
    BudgetMs = 1.5,
    MaxItemsPerFrame = 160,
    ReapplyInterval = 0.25,
  }

  local function applyScenePolicy(object, target, watch, masks)
    if masks[object] then
      if object:IsA("BasePart") then
        target.LocalTransparencyModifier = 1
      elseif object:IsA("Decal") or object:IsA("Texture") then
        target.Transparency = 1
      elseif object:IsA("Humanoid") then
        target.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
      elseif object:IsA("ForceField") or object:IsA("Explosion") or object:IsA("PVAdornment") then
        target.Visible = false
      else
        target.Enabled = false
      end
      watch = not object:IsA("BasePart")
    end
    return target, watch
  end
  local session, observer, shutdown
  local working, revision = false, 0
  local function setting(key)
    local value = Utils and Utils.getConfigValue(key)
    if value == nil then
      return CONFIG.defaults[key]
    end
    return value
  end
  local function requestedProfile()
    local profile = table.clone(PROFILE)
    local distance = tonumber(setting("AntiLagRenderDistance"))
    if not distance or distance ~= distance or math.abs(distance) == math.huge then
      distance = CONFIG.defaults.AntiLagRenderDistance
    end
    profile.CullDistance = math.clamp(distance, 300, 1200)
    local removeEffects = setting("AntiLagRemoveEffects") == true
    profile.GameSwordSounds = not setting("AntiLagRemoveSwordSounds")
    profile.CullFloorEnabled = setting("AntiLagFloorCull") == true
    profile.Particles, profile.TrailsAndBeams, profile.LegacyEffects = removeEffects, removeEffects, removeEffects
    profile.GameNoVFX, profile.GameReducedUI = removeEffects, removeEffects
    return profile
  end
  local function startSession()
    local player = Utils.getLocalPlayer()
    assert(player, "LocalPlayer indisponível")
    local workspace = game:GetService("Workspace")
    local lighting, runService = game:GetService("Lighting"), game:GetService("RunService")
    local replicated = game:GetService("ReplicatedStorage")
    local owner = {
      masks = setmetatable({}, { __mode = "k" }),
      closed = false,
      profile = requestedProfile(),
      runService = runService,
      replicated = replicated,
      compatible = adapter.isAvailable(),
      scope = lifetime.scope(),
    }

    session = owner
    local gameSettings
    pcall(function() gameSettings = UserSettings():GetService("UserGameSettings") end)
    local visualRoots = { workspace }
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if playerGui then
      visualRoots[#visualRoots + 1] = playerGui
    end
    local optimizerRoots = table.clone(visualRoots)
    optimizerRoots[#optimizerRoots + 1], optimizerRoots[#optimizerRoots + 2] = lighting, game:GetService("SoundService")
    owner.engine = properties.create({
      Workspace = workspace,
      Lighting = lighting,
      RunService = runService,
      PhasesPerFrame = 2,
      CollectionService = game:GetService("CollectionService"),
      GameSettings = gameSettings,
      Roots = optimizerRoots,
      ExtraPolicy = function(object, target, watch, options)
        target, watch = applyScenePolicy(object, target, watch, owner.masks)
        if owner.compatible then
          target, watch = adapter.apply(object, target, watch, options)
        end
        return target, watch
      end,
    }, owner.profile)
    local function getOption(key) return owner.engine:GetOption(key) end
    if owner.compatible then
      local scripts = player:FindFirstChild("PlayerScripts")
      owner.adapter = adapter.create({ Workspace = workspace, Player = player, PlayerScripts = scripts, ReplicatedStorage = replicated }, getOption)
    end
    local function viewedCharacter() return player.Character end
    owner.spatial = spatial.create({
      Workspace = workspace,
      Roots = visualRoots,
      Player = player,
      RunService = runService,
      PhasesPerFrame = 2,
      ConnectPhysics = function(callback)
        local scope = owner.scope.child()
        scheduler.connectPhysics(scope, callback)
        return { Disconnect = scope.destroy }
      end,
      GetFocusY = function()
        local character = viewedCharacter()
        local root = character and character:FindFirstChild("HumanoidRootPart")
        return root and root.Position.Y or nil
      end,
      GetFloorY = function()
        if not getOption("CullFloorEnabled") then
          return nil
        end
        local character = viewedCharacter()
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root and humanoid and humanoid.Health > 0 then
          local footY = root.Position.Y - humanoid.HipHeight - root.Size.Y * 0.5
          owner.floorY = owner.floorY and math.min(owner.floorY, footY) or footY
        end
        return owner.floorY and owner.floorY - 2 or nil
      end,
      GetFocusPosition = function()
        local character = viewedCharacter()
        local root = character and character:FindFirstChild("HumanoidRootPart")
        return root and root.Position or nil
      end,
      OnHidden = function(object, hidden)
        owner.masks[object] = if hidden then true else nil
        owner.engine:RefreshInstance(object, true)
        if hidden and (object:IsA("ParticleEmitter") or object:IsA("Trail")) then
          pcall(function() object:Clear() end)
        end
      end,
    }, getOption, PROFILE)
    owner.engine:SetEnabled(true)
    if owner.adapter then
      owner.adapter:SetEnabled(true)
    end
    owner.spatial:SetEnabled(true)
  end
  local function stopSession()
    local owner = session
    if not owner then
      return
    end
    owner.closed = true
    owner.scope.destroy()
    if owner.spatial then
      owner.spatial:Destroy()
    end
    if owner.adapter then
      owner.adapter:Destroy()
    end
    if owner.engine then
      owner.engine:Destroy()
      while owner.engine:GetStatus().Alive do
        owner.runService.Heartbeat:Wait()
      end
    end
    if session == owner then
      session = nil
    end
  end
  local function updateSession()
    local profile, owner = requestedProfile(), session
    local spatialChanged = profile.CullDistance ~= owner.profile.CullDistance or profile.CullFloorEnabled ~= owner.profile.CullFloorEnabled
    for key, value in pairs(profile) do
      if owner.profile[key] ~= value then
        owner.engine:SetOption(key, value)
      end
    end
    owner.profile = profile
    if owner.adapter then
      owner.adapter:Refresh()
    end
    if spatialChanged then
      owner.spatial:Refresh()
    end
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
        local ok, err = pcall(function()
          if Utils and Utils.isActive() and setting("AntiLagEnabled") then
            if session then
              updateSession()
            else
              startSession()
            end
          else
            stopSession()
          end
        end)
        if not ok then
          local reporting = Utils
          local cleaned, cleanupError = pcall(stopSession)
          if reporting then
            reporting.recordError("AntiLag", tostring(err))
          end
          if not cleaned then
            warn("[Exodus AntiLag] Falha ao restaurar: " .. tostring(cleanupError))
          end
        end
      until seen == revision
      working = false
    end)
  end
  function AntiLag.setEnabled(enabled)
    if not Utils then
      return false, "recurso indisponível"
    end
    return Utils.setConfig({ AntiLagEnabled = enabled == true })
  end
  function AntiLag.getStatus()
    local owner = session
    return {
      enabled = owner ~= nil and not owner.closed,
      busy = working,
      engine = owner and owner.engine and owner.engine:GetStatus() or nil,
      spatial = owner and owner.spatial and owner.spatial:GetStatus() or nil,
      generators = owner and owner.adapter and owner.adapter:GetStatus() or nil,
    }
  end
  function AntiLag.teardown()
    local previous = Utils
    Utils = nil
    revision += 1
    if observer then
      observer:Disconnect()
      observer = nil
    end
    if shutdown then
      shutdown.Connected = false
      if previous then
        previous.untrackGlobal(shutdown)
      end
      shutdown = nil
    end
    while working do
      game:GetService("RunService").Heartbeat:Wait()
    end
    stopSession()
    return true
  end
  function AntiLag.setup(deps)
    if type(deps) ~= "table" or type(deps.Utils) ~= "table" then
      return false, "dependência ausente: Utils"
    end
    AntiLag.teardown()
    Utils = deps.Utils
    properties, adapter, spatial = deps.Properties, deps.Adapter, deps.Spatial
    lifetime, scheduler = deps.Lifetime, deps.Controller
    observer = Utils.observeConfig(function(changes)
      for key in pairs(changes) do
        if CONFIG.schema[key] then
          if session or setting("AntiLagEnabled") then
            reconcile()
          end
          return
        end
      end
    end)
    shutdown = { Connected = true }
    function shutdown:Disconnect()
      if not self.Connected then
        return
      end
      self.Connected = false
      AntiLag.teardown()
    end
    Utils.trackGlobal(shutdown)
    if setting("AntiLagEnabled") then
      reconcile()
    end
    return true
  end
  AntiLag.__config = CONFIG
  AntiLag.__contract = {
    requires = {
      Lifetime = "lifetime",
      Controller = "universalcontroller",
      Properties = "renderproperties",
      Adapter = "renderadapter",
      Spatial = "renderspatial",
      Utils = "utils",
    },
    requiresMethods = {
      Lifetime = { "scope" },
      Controller = { "connectPhysics" },
      Properties = { "create" },
      Adapter = { "create", "apply", "isAvailable" },
      Spatial = { "create" },
      Utils = { "getConfigValue", "setConfig", "getLocalPlayer", "isActive", "observeConfig", "trackGlobal", "untrackGlobal", "recordError" },
    },
    provides = { "setup", "teardown", "setEnabled", "getStatus" },
  }
  return AntiLag
end)()

return { __bundle = { renderadapter = __part_renderadapter, antilag = __part_antilag } }
