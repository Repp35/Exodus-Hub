-- [[ anti lag ]]

-- module
local AntiLag = {}
local Utils

-- configuration
local CONFIG = {
  schema = {
    AntiLagEnabled = "boolean",
    AntiLagRenderDistance = "rate",
    AntiLagRemoveLighting = "boolean",
    AntiLagRemoveSwordSounds = "boolean",
    AntiLagHideLobby = "boolean",
    AntiLagRemoveFog = "boolean",
    AntiLagRemoveEffects = "boolean",
    AntiLagDisableTextures = "boolean",
  },
  defaults = {
    AntiLagEnabled = false,
    AntiLagRenderDistance = 160,
    AntiLagRemoveLighting = true,
    AntiLagRemoveSwordSounds = true,
    AntiLagHideLobby = true,
    AntiLagRemoveFog = false,
    AntiLagRemoveEffects = true,
    AntiLagDisableTextures = true,
  },
}

-- profile
local PROFILE = {
  StartEnabled = false,
  ShowMenu = false,
  CullEnabled = true,
  CullOcclusion = true,
  HideLobbyInMatch = true,
  GameSwordSounds = false,
  CullDistance = 160,
  CullInterval = 0.05,
  CullBudgetMs = 0.65,
  DisableTextures = true,
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
  FlatMaterials = true,
  HideTaggedDecorations = true,
  LowestGraphics = true,
  MaintainEffects = true,
  RestoreLatest = false,
  ShowFPS = false,
  FlatSkyTexture = "",
  BudgetMs = 0.8,
  MaxItemsPerFrame = 96,
  ReapplyInterval = 0.25,
}

local function createOptimizer(services, initialConfig)
  local Workspace = services.Workspace; local Lighting = services.Lighting
  local roots = services.Roots or { Workspace, Lighting }; local CollectionService = services.CollectionService
  local Heartbeat = services.RunService.Heartbeat; local options = table.clone(initialConfig)
  local controller = {}; local enabled, alive, destroying = false, true, false
  local journal, records = {}, {}; local connections = {}
  local stagedByParent = {}; local pending, queued, head, tail = {}, {}, 1, 0
  local scan = {}; local dirty = {}
  local delayed = false; local workerRunning = false
  local generation = 0; local unsupported = {}
  local unsupportedCount, restoreFailures, runtimeFailures = 0, 0, 0; local changedProperties = 0
  local scheduleWorker, enqueue, process, restartScan
  local oneSequence = NumberSequence.new(1); local zeroLifetime = NumberRange.new(0)
  local white, black = Color3.new(1, 1, 1), Color3.new(0, 0, 0); local skyProperties = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }
  local function read(object, property)
    return pcall(function() return object[property] end)
  end
  local function write(object, property, value)
    return pcall(function() object[property] = value end)
  end
  local function reportUnavailable(key)
    if not unsupported[key] then
      unsupported[key] = true; unsupportedCount += 1
      warn("[AntiLag] Ajuste indisponivel neste cliente: " .. key)
    end
  end
  local function unavailable(object, property) reportUnavailable(object.ClassName .. "." .. property) end
  local function inScope(object)
    for _, root in ipairs(roots) do
      if object == root or object:IsDescendantOf(root) then return true end
    end
    return false
  end
  local function isCharacterObject(object)
    local ancestor = object.Parent
    while ancestor and ancestor ~= Workspace do
      if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then return true end
      ancestor = ancestor.Parent
    end
    return false
  end
  local function desiredFor(object)
    local target = {}; local watch = true
    if object == services.GameSettings then
      if options.LowestGraphics then target.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1 end
      return target, false
    elseif object == Lighting then
      if options.Shadows then target.GlobalShadows = false end
      if options.FlatLighting then
        target.Ambient, target.OutdoorAmbient = white, white; target.Brightness, target.ExposureCompensation = 0, 0
        target.EnvironmentDiffuseScale, target.EnvironmentSpecularScale = 0, 0; target.ColorShift_Top, target.ColorShift_Bottom = black, black
        local ok, soft = pcall(function() return Enum.LightingStyle.Soft end)
        if ok then target.LightingStyle = soft end
        target.PrioritizeLightingQuality = false
      end
      if options.NoFog then target.FogStart, target.FogEnd = 0, 1000000
      else target.FogStart, target.FogEnd = math.max(0, options.CullDistance - 48), options.CullDistance; target.FogColor = Color3.fromRGB(150, 158, 168) end
    elseif object:IsA("Terrain") then
      if options.Water then
        target.WaterWaveSize, target.WaterWaveSpeed, target.WaterReflectance = 0, 0, 0
        target.WaterTransparency = if options.TransparentWater then 1 else 0
      end
      if options.TerrainDecoration then target.Decoration = false end
    elseif object:IsA("ParticleEmitter") then
      if options.Particles then
        target.Enabled = false; target.Lifetime = zeroLifetime
        target.Transparency = oneSequence; target.LocalTransparencyModifier = 1
      end
    elseif object:IsA("Trail") or object:IsA("Beam") then
      if options.TrailsAndBeams then target.Enabled, target.Transparency = false, oneSequence end
    elseif object:IsA("Smoke") then
      if options.LegacyEffects then target.Enabled, target.Opacity, target.LocalTransparencyModifier = false, 0, 1 end
    elseif object:IsA("Fire") then
      if options.LegacyEffects then target.Enabled, target.LocalTransparencyModifier = false, 1 end
    elseif object:IsA("Sparkles") then
      if options.LegacyEffects then target.Enabled, target.LocalTransparencyModifier = false, 1 end
    elseif object:IsA("Highlight") then
      if options.LegacyEffects then target.Enabled = false end
    elseif object:IsA("ForceField") or object:IsA("Explosion") then
      if options.LegacyEffects then target.Visible = false end
    elseif object:IsA("PostEffect") then
      if options.PostEffects then target.Enabled = false end
    elseif object:IsA("Light") then
      if options.Lights then target.Enabled = false end
      if options.Shadows then target.Shadows = false end
    elseif object:IsA("Atmosphere") then
      if options.Atmosphere then target.Density, target.Haze, target.Glare = 0, 0, 0 end
    elseif object:IsA("Clouds") then
      if options.Clouds then target.Enabled = false end
    elseif object:IsA("Sky") then
      if options.FlatSky then
        target.CelestialBodiesShown, target.StarCount = false, 0
        for _, property in ipairs(skyProperties) do
          target[property] = options.FlatSkyTexture
        end
      end
    elseif object:IsA("Decal") or object:IsA("Texture") then
      if options.DisableTextures then target.Transparency, target.Texture = 1, "" end
      watch = options.DisableTextures
    elseif object:IsA("SpecialMesh") then
      if options.DisableTextures then target.TextureId = "" end
      watch = false
    elseif object:IsA("SurfaceAppearance") then
      if options.DisableTextures then target.Parent = services.HiddenVisuals end
      watch = false
    elseif object:IsA("Shirt") then
      if options.DisableTextures then target.ShirtTemplate = "" end
      watch = false
    elseif object:IsA("Pants") then
      if options.DisableTextures then target.PantsTemplate = "" end
      watch = false
    elseif object:IsA("ShirtGraphic") then
      if options.DisableTextures then target.Graphic = "" end
      watch = false
    elseif object:IsA("BasePart") then
      watch = false
      if options.DisableTextures and object:IsA("MeshPart") then target.TextureID = "" end
      if options.FlatMaterials then target.Reflectance = 0 end
      if options.Shadows then target.CastShadow = false end
      if not isCharacterObject(object) then
        if options.FlatMaterials then target.Material = Enum.Material.SmoothPlastic; target.MaterialVariant, target.Reflectance = "", 0 end
        if options.HideTaggedDecorations and CollectionService:HasTag(object, "AntiLagDecoration") then target.LocalTransparencyModifier = 1 end
      end
    end
    return target, watch and options.MaintainEffects
  end
  local function clearStage(entry)
    local parent = entry.stagedParent
    if not parent then return end
    local objects = stagedByParent[parent]
    if objects then
      objects[entry.object] = nil
      if next(objects) == nil then stagedByParent[parent] = nil end
    end
    entry.stagedParent = nil
  end
  local function removeEntry(entry)
    clearStage(entry)
    if entry.connection then entry.connection:Disconnect(); entry.connection = nil end
    journal[entry.object] = nil; local index = entry.index
    local last = records[#records]; records[index] = last
    if last then last.index = index end
    records[#records] = nil
  end
  local function restoreProperty(object, property, saved)
    local ok, current = read(object, property)
    if options.RestoreLatest and ok and current ~= saved.applied then saved.original = current end
    if ok and current == saved.original then return end
    if not write(object, property, saved.original) then
      if property == "Parent" and object:IsA("SurfaceAppearance") and object.Parent == services.HiddenVisuals then
        pcall(function() object:Destroy() end)
      else
        restoreFailures += 1
      end
    end
  end
  local function restoreEntry(entry)
    removeEntry(entry)
    for property, saved in pairs(entry.properties) do
      restoreProperty(entry.object, property, saved); changedProperties -= 1
    end
  end
  local function delayDirty()
    if delayed then return end
    delayed = true
    task.delay(options.ReapplyInterval, function()
      delayed = false; local batch = dirty
      dirty = {}
      if not alive or not enabled then return end
      for object in pairs(batch) do
        enqueue(object)
      end
    end)
  end
  local function updateWatcher(entry, watch)
    if not watch then
      if entry.connection then entry.connection:Disconnect(); entry.connection = nil end
      return
    end
    if entry.connection then return end
    local function changed(property)
      if not enabled or not alive or journal[entry.object] ~= entry then return end
      local saved = entry.properties[property]
      if not saved then return end
      local ok, current = read(entry.object, property)
      if not ok or current == saved.applied then return end
      if options.RestoreLatest then saved.original = current end
      dirty[entry.object] = true; delayDirty()
    end
    if entry.object:IsA("BasePart") then
      entry.connection = entry.object:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function() changed("LocalTransparencyModifier") end)
    else
      entry.connection = entry.object.Changed:Connect(changed)
    end
  end
  process = function(object)
    local stagedEntry = journal[object]
    if stagedEntry and stagedEntry.stagedParent and not inScope(stagedEntry.stagedParent) then restoreEntry(stagedEntry); return end
    local special = object == services.GameSettings
    if not enabled or (not special and not inScope(object)) then
      if journal[object] then restoreEntry(journal[object]) end
      return
    end
    local target, watch = desiredFor(object)
    if services.ExtraPolicy then target, watch = services.ExtraPolicy(object, target, watch, options) end
    local entry = journal[object]
    if entry then
      for property, saved in pairs(entry.properties) do
        if target[property] == nil then
          if property == "Parent" then clearStage(entry) end
          entry.properties[property] = nil; restoreProperty(object, property, saved)
          changedProperties -= 1
        end
      end
    end
    for property, value in pairs(target) do
      if unsupported[object.ClassName .. "." .. property] then continue end
      local ok, current = read(object, property)
      if not ok then unavailable(object, property); continue end
      local saved = entry and entry.properties[property]
      if not saved and current == value and not watch then continue end
      if not entry then entry = { object = object, properties = {}, index = #records + 1 }; journal[object], records[entry.index] = entry, entry end
      if not saved then
        saved = { original = current, applied = current }; entry.properties[property] = saved
        changedProperties += 1
        if property == "Parent" and object:IsA("SurfaceAppearance") and current then
          entry.stagedParent = current; stagedByParent[current] = stagedByParent[current] or {}
          stagedByParent[current][object] = true
        end
      elseif options.RestoreLatest and current ~= saved.applied then
        saved.original = current
      end
      if current ~= value then
        local previous = saved.applied; saved.applied = value
        if not write(object, property, value) then
          saved.applied = previous; unavailable(object, property)
          if saved.original == current then entry.properties[property] = nil; changedProperties -= 1 end
        end
      else
        saved.applied = value
      end
    end
    if entry then
      if next(entry.properties) == nil then removeEntry(entry) else updateWatcher(entry, watch) end
    end
  end
  local function popPending()
    if head > tail then return nil end
    local object = pending[head]; pending[head] = nil
    head += 1; queued[object] = nil
    if head > tail then pending, head, tail = {}, 1, 0 end
    return object
  end
  local function nextScan()
    while #scan > 0 do
      local frame = scan[#scan]; local object = frame.items[frame.index]
      if not object then scan[#scan] = nil; continue end
      frame.index += 1
      local ok, children = pcall(function() return object:GetChildren() end)
      if ok and #children > 0 then scan[#scan + 1] = { items = children, index = 1 } end
      return object
    end
    return nil
  end
  local function workAvailable() return if enabled then head <= tail or #scan > 0 else #records > 0 end
  local function finishDestroy()
    alive = false
    for _, connection in ipairs(connections) do
      connection:Disconnect()
    end
    connections, dirty, pending, queued, scan = {}, {}, {}, {}, {}
  end
  scheduleWorker = function()
    if workerRunning or not alive then return end
    workerRunning = true
    task.defer(function()
      while alive and workAvailable() do
        local deadline = os.clock() + options.BudgetMs / 1000; local count = 0
        repeat
          if not enabled then
            local entry = records[#records]
            if entry then restoreEntry(entry) end
          else
            local object
            if count % 2 == 0 then object = popPending() or nextScan() else object = nextScan() or popPending() end
            if object then
              local ok, message = pcall(process, object)
              if not ok then
                runtimeFailures += 1
                if runtimeFailures <= 3 then warn("[AntiLag] " .. tostring(message)) end
              end
            end
          end
          count += 1
        until count >= options.MaxItemsPerFrame or os.clock() >= deadline or not workAvailable()
        if workAvailable() then Heartbeat:Wait() end
      end
      workerRunning = false
      if destroying and not enabled and #records == 0 then finishDestroy() end
    end)
  end
  enqueue = function(object)
    if not alive or not enabled or queued[object] then return end
    tail += 1; pending[tail], queued[object] = object, true
    scheduleWorker()
  end
  restartScan = function()
    generation += 1; scan = { { items = table.clone(roots), index = 1 } }
    if services.GameSettings then enqueue(services.GameSettings) end
    if options.LowestGraphics and not services.GameSettings then reportUnavailable("UserGameSettings.SavedQualityLevel") end
    scheduleWorker()
  end
  for _, root in ipairs(roots) do
    connections[#connections + 1] = root.DescendantAdded:Connect(enqueue)
    connections[#connections + 1] = root.DescendantRemoving:Connect(function(object)
      if journal[object] then
        task.defer(function()
          if alive then enqueue(object) end
        end)
      end
      local staged = stagedByParent[object]
      if staged then
        for visual in pairs(staged) do
          task.defer(function()
            if alive then enqueue(visual) end
          end)
        end
      end
    end)
  end
  for _, signal in ipairs({
    CollectionService:GetInstanceAddedSignal("AntiLagDecoration"),
    CollectionService:GetInstanceRemovedSignal("AntiLagDecoration"),
  }) do
    connections[#connections + 1] = signal:Connect(enqueue)
  end
  connections[#connections + 1] = Workspace.DescendantAdded:Connect(function(object)
    if enabled and object:IsA("Humanoid") and object.Parent then scan[#scan + 1] = { items = { object.Parent }, index = 1 }; scheduleWorker() end
  end)
  function controller:RefreshInstance(object)
    if enabled and alive then enqueue(object) end
  end
  function controller:RefreshSubtree(object)
    if enabled and alive and object then scan[#scan + 1] = { items = { object }, index = 1 }; scheduleWorker() end
  end
  function controller:SetEnabled(value)
    if not alive or destroying or enabled == value then return end
    enabled = value; generation += 1
    if enabled then restartScan() else pending, queued, scan, dirty, head, tail = {}, {}, {}, {}, 1, 0; scheduleWorker() end
  end
  function controller:SetOption(key, value)
    if not alive or destroying or options[key] == nil then return false end
    if typeof(value) ~= typeof(options[key]) then return false end
    if key == "BudgetMs" then value = math.clamp(value, 0.25, 4) end
    if key == "MaxItemsPerFrame" then value = math.floor(math.clamp(value, 8, 1000)) end
    if key == "ReapplyInterval" then value = math.clamp(value, 0.1, 2) end
    local bounds = {
      CullDistance = { 64, 1200 },
      CullInterval = { 0.03, 0.35 },
      CullBudgetMs = { 0.2, 1.5 },
    }

    if bounds[key] then value = math.clamp(value, bounds[key][1], bounds[key][2]) end
    if options[key] == value then return true end
    options[key] = value; local noScan = key == "ShowFPS"
      or key == "ShowMenu"
      or key == "StartEnabled"
      or key == "BudgetMs"
      or key == "MaxItemsPerFrame"
      or key == "ReapplyInterval"
      or key == "RestoreLatest"
      or string.sub(key, 1, 4) == "Cull"
      or key == "HideLobbyInMatch"
    if enabled and not noScan then restartScan() end
    if enabled and key == "CullDistance" then enqueue(Lighting) end
    return true
  end
  function controller:GetOption(key) return options[key] end
  function controller:GetOriginalProperty(object, property)
    local entry = journal[object]; local saved = entry and entry.properties[property]
    if saved then return saved.original end
    return object[property]
  end
  function controller:GetStatus()
    return {
      Enabled = enabled,
      Alive = alive,
      Destroying = destroying,
      Busy = workerRunning or workAvailable(),
      Instances = #records,
      Properties = changedProperties,
      Unsupported = unsupportedCount,
      RestoreFailures = restoreFailures,
      RuntimeFailures = runtimeFailures,
      Generation = generation,
    }
  end
  function controller:Destroy()
    if not alive or destroying then return end
    self:SetEnabled(false); destroying = true
    if #records == 0 then finishDestroy() else scheduleWorker() end
  end
  for _, key in ipairs({ "BudgetMs", "MaxItemsPerFrame", "ReapplyInterval" }) do
    controller:SetOption(key, options[key])
  end
  controller:SetEnabled(options.StartEnabled); return controller
end
local function createGameAdapter(services, getOption)
  local adapter = {}; local active, alive = false, true
  local modules = {}; local patches, attributes = {}, {}
  local connections = {}; local scheduled = false
  local refresh
  local stats = { DroppedVFX = 0, DroppedAudio = 0, RestoreConflicts = 0, Failures = 0 }; local Workspace = services.Workspace
  local player = services.Player
  local function enabledOption(key) return active and getOption(key) == true end
  local function deferRefresh()
    if scheduled or not alive then return end
    scheduled = true
    task.delay(0.25, function()
      scheduled = false
      if alive and active then refresh() end
    end)
  end
  local function reconcileAttribute(object, key, desired, wanted)
    local byKey = attributes[object]; local saved = byKey and byKey[key]
    if not wanted then
      if saved then
        byKey[key] = nil
        if saved.connection then saved.connection:Disconnect() end
        local ok = pcall(function() object:SetAttribute(key, saved.original) end)
        if not ok then stats.Failures += 1 end
        if next(byKey) == nil then attributes[object] = nil end
      end
      return
    end
    if not saved then
      local ok, original = pcall(function() return object:GetAttribute(key) end)
      if not ok then stats.Failures += 1; return end
      if not byKey then byKey = {}; attributes[object] = byKey end
      saved = { original = original, applied = desired }; byKey[key] = saved
      saved.connection = object:GetAttributeChangedSignal(key):Connect(function()
        if not active or not alive then return end
        local value = object:GetAttribute(key)
        if value ~= saved.applied then
          if getOption("RestoreLatest") then saved.original = value end
          deferRefresh()
        end
      end)
    end
    saved.applied = desired
    local ok = pcall(function()
      if object:GetAttribute(key) ~= desired then object:SetAttribute(key, desired) end
    end)
    if not ok then stats.Failures += 1 end
  end
  local function removePatch(id)
    local patch = patches[id]
    if not patch then return end
    patches[id] = nil
    if patch.object[patch.key] == patch.wrapper then
      local ok = pcall(function() patch.object[patch.key] = patch.original end)
      if not ok then stats.Failures += 1 end
    else
      stats.RestoreConflicts += 1
    end
  end
  local function ensurePatch(moduleName, key, shouldBlock, category, replacement)
    local id = moduleName .. "." .. key; local object = modules[moduleName]
    local wanted = active and getOption("GameGenerators") and type(object) == "table"
    if not wanted then removePatch(id); return end
    if patches[id] then return end
    local original = object[key]
    if type(original) ~= "function" then return end
    local wrapper = function(...)
      if alive and active and getOption("GameGenerators") and shouldBlock(...) then
        if category then stats[category] += 1 end
        if replacement then return replacement(...) end
        return nil
      end
      return original(...)
    end
    local ok = pcall(function() object[key] = wrapper end)
    if ok then patches[id] = { object = object, key = key, original = original, wrapper = wrapper } else stats.Failures += 1 end
  end
  refresh = function()
    if not alive then return end
    if not active then
      for object, byKey in pairs(attributes) do
        for key in pairs(byKey) do
          reconcileAttribute(object, key, nil, false)
        end
      end
    end
    local noVFX = enabledOption("GameNoVFX"); local quiet = enabledOption("GameCosmeticAudio")
    local reducedUI = enabledOption("GameReducedUI"); reconcileAttribute(Workspace, "LowQualityMode", true, active)
    reconcileAttribute(Workspace, "ShowAuras", false, noVFX); reconcileAttribute(player, "Setting_WeaponVFX", false, noVFX)
    reconcileAttribute(player, "Setting_ExplosionVFX", false, noVFX); reconcileAttribute(player, "Setting_KillSounds", false, quiet or active and getOption("GameSwordSounds") == false)
    reconcileAttribute(player, "Setting_SwordSounds", false, active and getOption("GameSwordSounds") == false)
    for _, method in ipairs({ "Spawn", "SpawnAtCFrame", "SpawnSwordEffect", "Emit", "Toggle" }) do
      ensurePatch("VFX", method, function() return enabledOption("GameNoVFX") end, "DroppedVFX")
    end
    ensurePatch("LowQuality", "CanSpawn", function() return enabledOption("GameNoVFX") end, nil, function() return false end)
    ensurePatch("VFXBudget", "Take", function() return enabledOption("GameNoVFX") end, nil, function() return false end)
    ensurePatch("WindowAnim", "ReducedMotion", function() return enabledOption("GameReducedUI") end, nil, function() return true end)
    ensurePatch("SFX", "SpawnSwordSFX", function(_, _, action)
      if getOption("GameSwordSounds") == false then return true end
      if not enabledOption("GameCosmeticAudio") then return false end
      if getOption("GameKeepCombatAudio") and (action == "BallHit" or action == "Block") then return false end
      return true
    end, "DroppedAudio")
    local emitter = services.PlayerScripts:FindFirstChild("Emitter2D"); local emitterModule = emitter and emitter:FindFirstChild("Emitter2D")
    if emitterModule and emitterModule:IsA("ModuleScript") then reconcileAttribute(emitterModule, "Enabled", false, reducedUI) end
  end
  function adapter:SetModule(name, value)
    if not alive or type(value) ~= "table" then return false end
    modules[name] = value
    if active then refresh() end
    return true
  end
  function adapter:SetEnabled(value)
    if not alive then return end
    active = value; refresh()
  end
  function adapter:Refresh()
    if active and alive then refresh() end
  end
  function adapter:GetStatus()
    local patchCount, attributeCount = 0, 0
    for _ in pairs(patches) do
      patchCount += 1
    end
    for _, entries in pairs(attributes) do
      for _ in pairs(entries) do
        attributeCount += 1
      end
    end
    return {
      Active = active,
      Patches = patchCount,
      Attributes = attributeCount,
      DroppedVFX = stats.DroppedVFX,
      DroppedAudio = stats.DroppedAudio,
      RestoreConflicts = stats.RestoreConflicts,
      Failures = stats.Failures,
    }
  end
  function adapter:Destroy()
    if not alive then return end
    self:SetEnabled(false); alive = false
    for _, connection in ipairs(connections) do
      connection:Disconnect()
    end
  end
  connections[#connections + 1] = services.PlayerScripts.DescendantAdded:Connect(function(object)
    if active and object.Name == "Emitter2D" then deferRefresh() end
  end)
  return adapter
end
local function applyGamePolicy(object, target, watch, options)
  if options.GameKeepIndicators then
    local critical = false
    if object:IsA("Highlight") then
      critical = object.Name == "PlayerBallHighlight" or object.Name == "LocalBlockCharacterHighlight"; local parent = object.Parent
      if parent then critical = critical or parent.Name == "GameBall" or parent.Name == "TrainingBall" or parent.Name == "ResilienceHitbox" end
    elseif object:IsA("Beam") then
      critical = object.Name == "PossessTether" or object.Name == "DarkForceChain"
    end
    if critical then target.Enabled, target.Transparency = nil, nil; watch = false end
  end
  if object:IsA("BasePart") then
    local ancestor = object
    while ancestor do
      if ancestor.Name == "GameBall" or ancestor.Name == "TrainingBall" then
        target.Material, target.MaterialVariant, target.Reflectance = nil, nil, nil; target.LocalTransparencyModifier = nil
        break
      end
      ancestor = ancestor.Parent
    end
  elseif object:IsA("SoundGroup") then
    if object.Parent and object.Parent.Name == "Master" then
      local mute = object.Name == "Music" and options.GameMuteMusic
        or object.Name == "Emotes" and options.GameCosmeticAudio
        or object.Name == "Ambience" and options.GameMuteAmbience
      if mute then target.Volume = 0; watch = options.MaintainEffects end
    end
  elseif object:IsA("Sound") then
    local kind = object:GetAttribute("SFXKind"); local swordMuted = options.GameSwordSounds == false and (kind == "SwordSounds" or kind == "KillSounds")
    if swordMuted or object.Name == "PB_LobbyTheme_Christmas" and options.GameMuteMusic then target.Volume = 0; watch = options.MaintainEffects end
  end
  return target, watch
end
local function worldHalf(frame, size)
  local r, u, l = frame.RightVector, frame.UpVector, frame.LookVector
  return Vector3.new(
    math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
    math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
    math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
  ) * 0.5
end
local function absolute(v) return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z)) end
local function cameraState(camera, distance)
  local frame = camera.CFrame; local vertical = math.tan(math.rad(camera.FieldOfView * 0.5))
  local horizontal = vertical * camera.ViewportSize.X / math.max(camera.ViewportSize.Y, 1)
  local normals = {
    frame.LookVector,
    frame.LookVector * horizontal + frame.RightVector,
    frame.LookVector * horizontal - frame.RightVector,
    frame.LookVector * vertical + frame.UpVector,
    frame.LookVector * vertical - frame.UpVector,
  }

  local planes = {}
  for i, normal in ipairs(normals) do
    planes[i] = { normal, absolute(normal) }
  end
  return { position = frame.Position, look = frame.LookVector, planes = planes, distance = distance }
end
local function boundsReason(center, half, camera, previous)
  local delta = center - camera.position; local gap = absolute(delta) - half
  local x, y, z = math.max(0, gap.X), math.max(0, gap.Y), math.max(0, gap.Z); local limit = camera.distance + (previous == "distance" and 0 or 8)
  if x * x + y * y + z * z > limit * limit then return "distance" end
  for _, plane in ipairs(camera.planes) do
    if delta:Dot(plane[1]) + half:Dot(plane[2]) < -1 then return "view" end
  end
  return nil
end
local function segmentInBox(origin, point, half)
  local direction = point - origin; local enter, leave = 0, 1
  for _, axis in ipairs({ "X", "Y", "Z" }) do
    local o, d, h = origin[axis], direction[axis], half[axis]
    if math.abs(d) < 0.000001 then
      if math.abs(o) > h then return false end
    else
      local a, b = (-h - o) / d, (h - o) / d
      if a > b then a, b = b, a end
      enter, leave = math.max(enter, a), math.min(leave, b)
      if enter > leave then return false end
    end
  end
  return enter > 0.0001 and leave < 0.9999 and leave - enter > 0.00001
end
local function boxOccludes(frame, blockerHalf, origin, center, half)
  local localOrigin = frame:PointToObjectSpace(origin)
  for x = -1, 1, 2 do
    for y = -1, 1, 2 do
      for z = -1, 1, 2 do
        local corner = center + Vector3.new(x * half.X, y * half.Y, z * half.Z)
        if not segmentInBox(localOrigin, frame:PointToObjectSpace(corner), blockerHalf) then return false end
      end
    end
  end
  return true
end
local function createOcclusionTester(workspace, visibleBlocker)
  local tester = {}; local used, total, terrainReads = 0, 0, 0
  local terrainBoxes, terrainCount = {}, 0; local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude; params.IgnoreWater = true
  local function solidPart(part)
    return part:IsA("Part")
      and part.Shape == Enum.PartType.Block
      and part.Anchored
      and part.Transparency <= 0.01
      and not part:FindFirstChildOfClass("SpecialMesh")
      and part:GetAttribute("AntiLagDecoration") ~= true
      and (not visibleBlocker or visibleBlocker(part))
  end
  function tester:BeginFrame(exclusions)
    used, terrainReads = 0, 0; params.FilterDescendantsInstances = exclusions
  end
  function tester:Test(entry, camera, center, half)
    local blocker = entry.blocker
    if
      blocker
      and blocker.Parent
      and solidPart(blocker)
      and boxOccludes(blocker.CFrame, blocker.Size * 0.5 - Vector3.new(0.02, 0.02, 0.02), camera.position, center, half)
    then
      return true
    end
    entry.blocker = nil; local terrainBox = entry.terrainBox
    if
      terrainBox
      and terrainBox.expires > os.clock()
      and terrainBox.solid
      and boxOccludes(terrainBox.frame, Vector3.new(1.9, 1.9, 1.9), camera.position, center, half)
    then
      return true
    end
    entry.terrainBox = nil
    if used >= 8 then return false end
    used, total = used + 1, total + 1; local result = workspace:Raycast(camera.position, center - camera.position, params)
    if not result then return false end
    blocker = result.Instance
    if solidPart(blocker) then
      if boxOccludes(blocker.CFrame, blocker.Size * 0.5 - Vector3.new(0.02, 0.02, 0.02), camera.position, center, half) then entry.blocker = blocker; return true end
    elseif blocker:IsA("Terrain") then
      local inside = result.Position - result.Normal * 6; local cell = Vector3.new(math.floor(inside.X / 4), math.floor(inside.Y / 4), math.floor(inside.Z / 4)) * 4
      local key = cell.X .. ":" .. cell.Y .. ":" .. cell.Z; terrainBox = terrainBoxes[key]
      if terrainBox and terrainBox.expires > os.clock() then
        entry.terrainBox = terrainBox; return terrainBox.solid and boxOccludes(terrainBox.frame, Vector3.new(1.9, 1.9, 1.9), camera.position, center, half)
      end
      if terrainReads >= 1 then return false end
      terrainReads = terrainReads + 1; local region = Region3.new(cell - Vector3.new(4, 4, 4), cell + Vector3.new(8, 8, 8))
      local ok, materials, occupancy = pcall(function() return blocker:ReadVoxels(region, 4) end)
      local solid = ok
      if ok then
        for x = 1, 3 do
          for y = 1, 3 do
            for z = 1, 3 do
              if occupancy[x][y][z] < 1 or materials[x][y][z] == Enum.Material.Air or materials[x][y][z] == Enum.Material.Water then solid = false end
            end
          end
        end
      end
      if terrainCount >= 64 then terrainBoxes, terrainCount = {}, 0 end
      if not terrainBoxes[key] then terrainCount = terrainCount + 1 end
      terrainBox = { frame = CFrame.new(cell + Vector3.new(2, 2, 2)), solid = solid, expires = os.clock() + 0.1 }; terrainBoxes[key], entry.terrainBox = terrainBox, terrainBox
      if solid then return boxOccludes(terrainBox.frame, Vector3.new(1.9, 1.9, 1.9), camera.position, center, half) end
    end
    return false
  end
  function tester:GetStatus() return { Rays = total, RaysThisFrame = used, MaxRaysPerFrame = 8, TerrainReadsThisFrame = terrainReads } end
  return tester
end
local function createSpatialController(services, getOption)
  local workspace, player = services.Workspace, services.Player; local controller = {}
  local active, alive = false, true; local records, cells, regions = {}, {}, {}
  local sceneIds, sceneSequence = setmetatable({}, { __mode = "k" }), 0; local pending, queued, stack = {}, {}, {}
  local head, tail = 1, 0; local cursor, auditCursor, regionSequence = 1, 1, 0
  local hiddenCount, trackedCount, failures = 0, 0, 0; local lobby, lobbyHidden, driver, job = nil, false, nil, nil
  local connections = {}; local nextCycle, remaining = 0, 0
  local function option(key, fallback)
    local value = getOption(key)
    if value == nil then return fallback end
    return value
  end
  local function setHidden(entry, hidden)
    if entry.hidden == hidden then return end
    entry.hidden = hidden; hiddenCount = hiddenCount + (hidden and 1 or -1)
    services.OnHidden(entry.object, hidden)
  end
  local function forget(object)
    local entry = records[object]
    if not entry then return end
    setHidden(entry, false); records[object], trackedCount = nil, trackedCount - 1
    local region = entry.region; local last = region.parts[#region.parts]
    region.parts[entry.index] = last
    if last then last.index = entry.index end
    region.parts[#region.parts] = nil; region.dirty = true
    if #region.parts == 0 then
      cells[region.key] = nil; local lastRegion = regions[#regions]
      regions[region.index] = lastRegion
      if lastRegion then lastRegion.index = region.index end
      regions[#regions] = nil
      if job and job.region == region then job = nil end
    end
  end
  local function protected(object)
    local ancestor = object
    while ancestor and ancestor ~= workspace do
      if ancestor.Name == "GameBall" or ancestor.Name == "TrainingBall" or ancestor.Name == "Ball" or ancestor:GetAttribute("AntiLagKeepVisible") == true then return true end
      if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then return true end
      ancestor = ancestor.Parent
    end
    return false
  end
  local function sceneFor(object)
    local ancestor, scene = object.Parent, nil
    while ancestor and ancestor ~= workspace do
      scene = ancestor
      if ancestor == lobby then return ancestor end
      if ancestor.Parent and ancestor.Parent.Name == "Maps" then return ancestor end
      ancestor = ancestor.Parent
    end
    return scene or object
  end
  local function register(object)
    if records[object] or not object:IsA("BasePart") or object:IsA("Terrain") or not object.Anchored or object.Transparency >= 0.99 or protected(object) then return end
    local position, half = object.Position, worldHalf(object.CFrame, object.Size); local scene = sceneFor(object)
    if not sceneIds[scene] then sceneSequence = sceneSequence + 1; sceneIds[scene] = sceneSequence end
    local key = sceneIds[scene] .. ":" .. math.floor(position.X / 32) .. ":" .. math.floor(position.Y / 32) .. ":" .. math.floor(position.Z / 32)
    if math.max(half.X, half.Y, half.Z) > 24 then regionSequence = regionSequence + 1; key = "large:" .. regionSequence end
    local bucket = cells[key]
    if not bucket then bucket = { key = key, scene = scene, parts = {}, index = #regions + 1, min = position - half, max = position + half }; cells[key], regions[bucket.index] = bucket, bucket end
    local lo, hi = position - half, position + half; bucket.min = Vector3.new(math.min(bucket.min.X, lo.X), math.min(bucket.min.Y, lo.Y), math.min(bucket.min.Z, lo.Z))
    bucket.max = Vector3.new(math.max(bucket.max.X, hi.X), math.max(bucket.max.Y, hi.Y), math.max(bucket.max.Z, hi.Z))
    bucket.center, bucket.half = (bucket.min + bucket.max) * 0.5, (bucket.max - bucket.min) * 0.5
    local entry = { object = object, frame = object.CFrame, size = object.Size, region = bucket, index = #bucket.parts + 1, hidden = false }; records[object], bucket.parts[entry.index] = entry, entry
    trackedCount = trackedCount + 1; bucket.dirty = true
    nextCycle = 0
  end
  local function enqueue(object)
    if not active or queued[object] or not object:IsA("BasePart") then return end
    tail = tail + 1; pending[tail], queued[object] = object, true
  end
  local function updateLobby()
    local gameRoot = workspace:FindFirstChild("Game"); local current = gameRoot and gameRoot:FindFirstChild("Lobby")
    if current ~= lobby then
      local previous = lobby; lobby = current
      services.OnLobbyHidden(false, previous); lobbyHidden = false
      if current then services.OnLobbyHidden(false, current) end
    end
    nextCycle = 0
  end
  local function nextNode()
    if head <= tail then
      local object = pending[head]; pending[head], queued[object] = nil, nil
      head = head + 1
      if head > tail then pending, head, tail = {}, 1, 0 end
      return object, false
    end
    while #stack > 0 do
      local frame = stack[#stack]; local object = frame.items[frame.index]
      if object then frame.index = frame.index + 1; return object, true end
      stack[#stack] = nil
    end
    return nil, false
  end
  local function regionReason(region, camera)
    if lobbyHidden and region.scene == lobby then return "lobby" end
    local reason = boundsReason(region.center, region.half, camera, region.reason)
    if not reason and option("CullOcclusion", true) and services.Occlusion:Test(region, camera, region.center, region.half) then reason = "occlusion" end
    return reason
  end
  function controller:Tick(now, camera)
    if not active or not alive or not camera then return end
    local deadline = os.clock() + option("CullBudgetMs", 0.65) / 1000; local snapshot = cameraState(camera, option("CullDistance", 160))
    local inMatch = workspace:GetAttribute("MatchStatus") == 6; local lives = tonumber(player:GetAttribute("Lives")) or 0
    local hideLobby = option("HideLobbyInMatch", true) and inMatch and lives > 0
    if services.IsLobbyCamera and services.IsLobbyCamera(snapshot.position) then hideLobby = false end
    if hideLobby ~= lobbyHidden then
      lobbyHidden = hideLobby; services.OnLobbyHidden(hideLobby, lobby)
      nextCycle = 0
    end
    local count = 0
    while count < 32 and os.clock() < deadline do
      local object, descend = nextNode()
      if not object then break end
      if object == workspace or object:IsDescendantOf(workspace) then
        if descend then
          local children = object:GetChildren()
          if #children > 0 then stack[#stack + 1] = { items = children, index = 1 } end
        end
        register(object)
      end
      count = count + 1
    end
    if #regions > 0 then
      if auditCursor > #regions then auditCursor = 1 end
      local region = regions[auditCursor]; auditCursor = auditCursor + 1
      region.audit = (region.audit or 0) % #region.parts + 1; local entry = region.parts[region.audit]
      if
        entry
        and (not entry.object:IsDescendantOf(workspace) or not entry.object.Anchored or entry.object.CFrame ~= entry.frame or entry.object.Size ~= entry.size)
      then
        local object = entry.object; forget(object)
        if object:IsDescendantOf(workspace) then register(object) end
      end
    end
    if remaining == 0 and now >= nextCycle then remaining, nextCycle = #regions, now + option("CullInterval", 0.05) end
    if job then
      local reason = regionReason(job.region, snapshot)
      if reason ~= job.reason then job.reason, job.index = reason, 1 end
    end
    while (remaining > 0 or job) and count < 160 and os.clock() < deadline do
      if not job then
        if #regions == 0 then remaining = 0; break end
        if cursor > #regions then cursor = 1 end
        local region = regions[cursor]; cursor, remaining = cursor + 1, remaining - 1
        local reason = regionReason(region, snapshot)
        if reason ~= region.reason or region.dirty then job = { region = region, reason = reason, index = 1 } end
      end
      if job then
        local entry = job.region.parts[job.index]
        if entry then setHidden(entry, job.reason ~= nil); job.index = job.index + 1 else job.region.reason, job.region.dirty = job.reason, false; job = nil end
      end
      count = count + 1
    end
  end
  local function clear()
    for _, entry in pairs(records) do
      setHidden(entry, false)
    end
    records, cells, regions, pending, queued, stack = {}, {}, {}, {}, {}, {}; sceneIds, sceneSequence = setmetatable({}, { __mode = "k" }), 0
    head, tail, cursor, auditCursor, remaining, trackedCount = 1, 0, 1, 1, 0, 0; job, nextCycle = nil, 0
    lobbyHidden = false; services.OnLobbyHidden(false, lobby)
  end
  function controller:SetEnabled(value)
    if not alive or active == value then return end
    active = value
    if driver then driver:Disconnect(); driver = nil end
    clear()
    if active then
      updateLobby(); stack = { { items = { workspace }, index = 1 } }
      driver = services.RunService.Heartbeat:Connect(function()
        local ok, message = pcall(function()
          services.BeginFrame(); controller:Tick(os.clock(), workspace.CurrentCamera)
        end)
        if not ok then
          failures = failures + 1
          if failures <= 3 then warn("[AntiLag regions] " .. tostring(message)) end
        end
      end)
    end
  end
  function controller:Refresh() nextCycle = 0 end
  function controller:GetStatus()
    return {
      Tracked = trackedCount,
      Hidden = hiddenCount,
      Chunks = #regions,
      LobbyHidden = lobbyHidden,
      Indexing = #stack > 0 or head <= tail,
      RuntimeFailures = failures,
    }
  end
  function controller:Destroy()
    if not alive then return end
    self:SetEnabled(false); alive = false
    for _, connection in ipairs(connections) do
      connection:Disconnect()
    end
  end
  connections[#connections + 1] = workspace.DescendantAdded:Connect(function(object)
    enqueue(object)
    if object.Name == "Lobby" then updateLobby() end
  end)
  connections[#connections + 1] = workspace.DescendantRemoving:Connect(function(object) forget(object) end)
  connections[#connections + 1] = workspace:GetAttributeChangedSignal("MatchStatus"):Connect(updateLobby)
  connections[#connections + 1] = player:GetAttributeChangedSignal("Lives"):Connect(updateLobby); return controller
end
local function visualObject(object)
  return object:IsA("BasePart")
    or object:IsA("BillboardGui")
    or object:IsA("SurfaceGui")
    or object:IsA("ParticleEmitter")
    or object:IsA("Trail")
    or object:IsA("Beam")
    or object:IsA("Light")
end
local function createRelevanceController(services, getOption)
  local controller = {}; local entries, roster, connections = {}, {}, {}
  local active, cursor, hidden, checks = false, 1, 0, 0; local camera, exclusions = nil, {}
  local function setHidden(entry, value)
    if entry.hidden == value then return end
    entry.hidden = value; hidden = hidden + (value and 1 or -1)
    for object in pairs(entry.visuals) do
      services.OnHidden(object, value)
    end
  end
  local function detach(entry)
    setHidden(entry, false)
    for _, connection in ipairs(entry.characterConnections) do
      connection:Disconnect()
    end
    entry.characterConnections, entry.visuals = {}, {}; entry.character, entry.root, entry.boxOffset, entry.halfSize = nil, nil, nil, nil
  end
  local function attach(entry, character)
    detach(entry); entry.character, entry.nextBounds, entry.nextCheck = character, 0, 0
    if not character then return end
    local function added(object)
      if object.Name == "HumanoidRootPart" and object:IsA("BasePart") then entry.root = object end
      if visualObject(object) then
        entry.visuals[object] = true
        if entry.hidden then services.OnHidden(object, true) end
      end
      entry.nextBounds, entry.nextCheck = 0, 0
    end
    for _, object in ipairs(character:GetDescendants()) do
      added(object)
    end
    entry.characterConnections[1] = character.DescendantAdded:Connect(added)
    entry.characterConnections[2] = character.DescendantRemoving:Connect(function(object)
      if entry.visuals[object] then services.OnHidden(object, false); entry.visuals[object] = nil end
      if object == entry.root then entry.root = nil end
      entry.nextBounds, entry.nextCheck = 0, 0
    end)
  end
  local function add(player)
    if player == services.Player or entries[player] then return end
    local entry = { player = player, visuals = {}, characterConnections = {}, connections = {}, index = #roster + 1, hidden = false }; entries[player], roster[entry.index] = entry, entry
    entry.connections[1] = player.CharacterAdded:Connect(function(character)
      if active then attach(entry, character) end
    end)
    entry.connections[2] = player.CharacterRemoving:Connect(function() detach(entry) end)
    if active then attach(entry, player.Character) end
  end
  local function remove(player)
    local entry = entries[player]
    if not entry then return end
    detach(entry)
    for _, connection in ipairs(entry.connections) do
      connection:Disconnect()
    end
    local last = roster[#roster]; roster[entry.index] = last
    if last then last.index = entry.index end
    roster[#roster], entries[player] = nil, nil
  end
  function controller:BeginFrame(now, currentCamera)
    table.clear(exclusions); local localCharacter = services.Player.Character
    if localCharacter then exclusions[#exclusions + 1] = localCharacter end
    for _, entry in ipairs(roster) do
      if entry.character then exclusions[#exclusions + 1] = entry.character end
    end
    services.Occlusion:BeginFrame(exclusions)
    if not active or not currentCamera then camera = nil; return end
    camera = cameraState(currentCamera, math.min(getOption("CullDistance") or 160, 220))
    for _ = 1, math.min(4, #roster) do
      if cursor > #roster then cursor = 1 end
      local entry = roster[cursor]; cursor = cursor + 1
      if now >= (entry.nextCheck or 0) then
        local root, character = entry.root, entry.character
        if root and character and root:IsDescendantOf(character) then
          if now >= entry.nextBounds or not entry.boxOffset then
            local ok, frame, size = pcall(function() return character:GetBoundingBox() end)
            if ok then entry.boxOffset, entry.halfSize = root.CFrame:ToObjectSpace(frame), size + Vector3.new(4, 4, 4) end
            entry.nextBounds = now + 0.5
          end
          if entry.boxOffset then
            local frame = root.CFrame * entry.boxOffset; local half = worldHalf(frame, entry.halfSize)
            local reason = boundsReason(frame.Position, half, camera, entry.reason)
            if not reason and services.Occlusion:Test(entry, camera, frame.Position, half) then reason = "occlusion" end
            entry.reason = reason; setHidden(entry, reason ~= nil)
            entry.distance = (root.Position - camera.position).Magnitude; checks = checks + 1
          end
        else
          setHidden(entry, false)
        end
        entry.nextCheck = now + 0.05
      end
    end
  end
  function controller:Interval(player)
    if player == services.Player then return 0 end
    local entry = entries[player]
    if not entry or not camera then return 0 end
    if entry.hidden then return math.huge end
    if (entry.distance or 0) <= 40 then return math.min(0.1, math.max(1 / 30, (#roster - hidden) / 120)) end
    return 0.1
  end
  function controller:SetEnabled(value)
    if active == value then return end
    active = value
    for _, entry in ipairs(roster) do
      if active then attach(entry, entry.player.Character) else detach(entry) end
    end
  end
  function controller:GetStatus() return { Players = #roster, Hidden = hidden, Checks = checks } end
  function controller:Destroy()
    self:SetEnabled(false)
    for _, connection in ipairs(connections) do
      connection:Disconnect()
    end
    while #roster > 0 do
      remove(roster[#roster].player)
    end
  end
  for _, player in ipairs(services.Players:GetPlayers()) do
    add(player)
  end
  connections[1] = services.Players.PlayerAdded:Connect(add); connections[2] = services.Players.PlayerRemoving:Connect(remove)
  return controller
end
local function createVisualScheduler(services, getOption)
  local scheduler = {}; local suspended, patches = {}, {}
  local animators = setmetatable({}, { __mode = "k" }); local scriptStates = {}
  local active, alive, delayed = false, true, false; local skipped, failures = 0, 0
  local connections = {}; local inspect = getconnections
  local upvalues = getupvalues or (debug and debug.getupvalues); local environment = getfenv
  local supported = type(inspect) == "function" and type(environment) == "function"
  local function restore()
    for connection in pairs(suspended) do
      local ok = pcall(function() connection:Enable() end)
      if not ok then failures = failures + 1 end
    end
    suspended = {}
    for script, enabled in pairs(scriptStates) do
      pcall(function() script.Enabled = enabled end)
    end
    scriptStates = {}
    for object, patch in pairs(patches) do
      if object.Update == patch.wrapper then object.Update = patch.original end
    end
    patches = {}
  end
  local function gateSword(class)
    if patches[class] then return end
    local original = rawget(class, "Update")
    if
      type(original) ~= "function"
      or type(rawget(class, "UpdateSwordThing")) ~= "function"
      or type(rawget(class, "UpdateAutomaticGrip")) ~= "function"
      or type(rawget(class, "BlendGrip")) ~= "function"
    then
      return
    end
    local states = setmetatable({}, { __mode = "k" })
    local wrapper = function(animator, dt, ...)
      local owner = animator.Owner
      if owner and owner ~= services.Player then animators[animator] = owner end
      if not active or not owner or owner == services.Player or animator.PrevChar ~= owner.Character then return original(animator, dt, ...) end
      local interval = services.Relevance:Interval(owner); local state = states[animator]
      if not state then state = { elapsed = 0 }; states[animator] = state end
      state.elapsed = math.min(state.elapsed + dt, 0.1)
      if interval == math.huge or state.elapsed < interval then skipped = skipped + 1; return nil end
      local elapsed = state.elapsed; state.elapsed = 0
      return original(animator, elapsed, ...)
    end
    local ok = pcall(function() class.Update = wrapper end)
    if ok then patches[class] = { original = original, wrapper = wrapper } else failures = failures + 1 end
  end
  local function refresh()
    if not alive or not active then return end
    local client = services.PlayerScripts:FindFirstChild("Client")
    if not client then return end
    local vfx = client:FindFirstChild("VFX"); local auraLoop = vfx and vfx:FindFirstChild("AuraVisibility")
    if auraLoop and auraLoop:IsA("LocalScript") and getOption("GameNoVFX") and scriptStates[auraLoop] == nil then
      local ok = pcall(function()
        scriptStates[auraLoop] = auraLoop.Enabled; auraLoop.Enabled = false
      end)
      if not ok then failures = failures + 1 end
    end
    if not supported then return end
    for _, signal in ipairs({ services.RunService.RenderStepped, services.RunService.Heartbeat }) do
      local ok, list = pcall(inspect, signal)
      if ok and type(list) == "table" then
        for _, connection in ipairs(list) do
          local inspected, callback, script = pcall(function()
            local fn = connection.Function; local env = type(fn) == "function" and environment(fn)
            return fn, env and rawget(env, "script")
          end)
          if inspected and typeof(script) == "Instance" and script:IsA("LocalScript") and script:IsDescendantOf(client) then
            local parent = script.Parent; local cosmetic = parent
              and (
                (parent.Name == "Gameplay" and script.Name == "HeadLook" and getOption("GameReducedHeadLook"))
                or (parent.Name == "VFX" and script.Name == "ChromaWeapon" and getOption("GameNoVFX"))
                or (parent.Name == "UI" and (script.Name == "GradientFX" or script.Name == "TileShimmer") and getOption("GameReducedUI"))
              )
            if cosmetic and not suspended[connection] then
              local disabled = pcall(function()
                if connection.Enabled == true then connection:Disable(); suspended[connection] = true end
              end)
              if not disabled then failures = failures + 1 end
            elseif parent and parent.Name == "Gameplay" and script.Name == "Animate" and type(upvalues) == "function" then
              local read, values = pcall(upvalues, callback)
              if read and type(values) == "table" then
                for _, value in pairs(values) do
                  if type(value) == "table" then gateSword(value) end
                end
              end
            end
          end
        end
      else
        failures = failures + 1
      end
    end
  end
  function scheduler:Refresh()
    restore(); refresh()
  end
  function scheduler:SetEnabled(value)
    active = value
    if active then
      refresh()
      for _, delay in ipairs({ 0.5, 1, 2, 5 }) do
        task.delay(delay, function()
          if active and alive then refresh() end
        end)
      end
    else
      restore()
    end
  end
  function scheduler:GetStatus()
    local callbacks, classes, scripts = 0, 0, 0
    for _ in pairs(scriptStates) do
      scripts = scripts + 1
    end
    for _ in pairs(suspended) do
      callbacks = callbacks + 1
    end
    for _ in pairs(patches) do
      classes = classes + 1
    end
    return {
      Supported = supported,
      SuspendedCallbacks = callbacks,
      SuspendedScripts = scripts,
      SwordClasses = classes,
      SkippedUpdates = skipped,
      Failures = failures,
    }
  end
  function scheduler:Destroy()
    self:SetEnabled(false); alive = false
    animators = setmetatable({}, { __mode = "k" })
    for _, connection in ipairs(connections) do
      connection:Disconnect()
    end
  end
  if services.Players then
    connections[#connections + 1] = services.Players.PlayerRemoving:Connect(function(player)
      for animator, owner in pairs(animators) do
        if owner == player then
          pcall(function() animator:ClearConnections() end)
          animators[animator] = nil
        end
      end
    end)
  end
  connections[#connections + 1] = services.PlayerScripts.DescendantAdded:Connect(function(object)
    if not active or delayed or not object:IsA("LocalScript") then return end
    delayed = true
    task.delay(0.5, function()
      delayed = false
      if active and alive then refresh() end
    end)
  end)
  return scheduler
end
local function applyScenePolicy(object, target, watch, options, masks, lobbyHidden, lobby)
  local masked = masks[object] == true; local ancestor = object.Parent
  while not masked and ancestor do
    masked = masks[ancestor] == true; ancestor = ancestor.Parent
  end
  if masked or lobbyHidden and lobby and object:IsDescendantOf(lobby) then
    if object:IsA("BasePart") and not object:IsA("Terrain") then
      target.LocalTransparencyModifier = 1; watch = options.MaintainEffects
    elseif
      object:IsA("BillboardGui")
      or object:IsA("SurfaceGui")
      or object:IsA("Highlight")
      or object:IsA("Light")
      or object:IsA("ParticleEmitter")
      or object:IsA("Trail")
      or object:IsA("Beam")
      or object:IsA("Smoke")
      or object:IsA("Fire")
      or object:IsA("Sparkles")
    then
      target.Enabled = false
    end
  end
  return target, watch
end

-- lifecycle
local session, observer, shutdown
local working, revision = false, 0
local function setting(key)
  local value = Utils and Utils.getConfigValue(key)
  if value == nil then return CONFIG.defaults[key] end
  return value
end
local function requestedProfile()
  local profile = table.clone(PROFILE); local distance = tonumber(setting("AntiLagRenderDistance")) or 160
  if distance ~= distance or distance == math.huge or distance == -math.huge then distance = 160 end
  profile.CullDistance = math.clamp(distance, 64, 1200); local removeLighting, removeEffects = setting("AntiLagRemoveLighting"), setting("AntiLagRemoveEffects")
  profile.Lights, profile.Shadows, profile.FlatLighting = removeLighting, removeLighting, removeLighting; profile.GameSwordSounds = not setting("AntiLagRemoveSwordSounds")
  profile.HideLobbyInMatch = setting("AntiLagHideLobby"); profile.NoFog = setting("AntiLagRemoveFog")
  profile.DisableTextures = setting("AntiLagDisableTextures"); profile.Particles, profile.TrailsAndBeams, profile.LegacyEffects = removeEffects, removeEffects, removeEffects
  profile.PostEffects, profile.Clouds, profile.FlatSky = removeEffects, removeEffects, removeEffects; profile.GameNoVFX, profile.GameReducedUI = removeEffects, removeEffects
  return profile
end
local function loadNativeModules(owner)
  if not owner.compatible then return end
  for _, spec in ipairs({
    { "VFX", "Core", "VFX", "VFX" },
    { "SFX", "Core", "SFX", "SFX" },
    { "LowQuality", "Core", "LowQuality", "LowQuality" },
    { "VFXBudget", "Core", "VFXBudget" },
    { "WindowAnim", "UI", "WindowAnim" },
  }) do
    task.spawn(function()
      local deadline, nativeModule = os.clock() + 10, nil
      repeat
        if owner.closed then return end
        local shared = owner.replicated:FindFirstChild("Shared"); local branch = shared and shared:FindFirstChild(spec[2])
        nativeModule = branch and branch:FindFirstChild(spec[3])
        if nativeModule then break end
        task.wait(0.25)
      until os.clock() >= deadline
      if owner.closed or not nativeModule or not nativeModule:IsA("ModuleScript") then return end
      local ok, result = pcall(require, nativeModule)
      if owner.closed then return end
      if ok and type(result) == "table" then
        owner.adapter:SetModule(spec[1], if spec[4] then result[spec[4]] else result)
      else
        warn("[Exodus AntiLag] Adaptador indisponível: " .. spec[1])
      end
    end)
  end
end
local function startSession()
  local player = Utils.getLocalPlayer(); assert(player, "LocalPlayer indisponível")
  local workspace = game:GetService("Workspace"); local lighting, runService = game:GetService("Lighting"), game:GetService("RunService")
  local replicated = game:GetService("ReplicatedStorage")
  local owner = {
    masks = setmetatable({}, { __mode = "k" }),
    closed = false,
    lobbyHidden = false,
    profile = requestedProfile(),
    runService = runService,
    replicated = replicated,
    compatible = game.PlaceId == 12979690461 or runService:IsStudio(),
  }

  session = owner; owner.hiddenVisuals = Instance.new("Folder")
  owner.hiddenVisuals.Name = "ExodusHiddenVisuals"
  local gameSettings
  pcall(function() gameSettings = UserSettings():GetService("UserGameSettings") end)
  owner.engine = createOptimizer({
    Workspace = workspace,
    Lighting = lighting,
    RunService = runService,
    CollectionService = game:GetService("CollectionService"),
    GameSettings = gameSettings,
    HiddenVisuals = owner.hiddenVisuals,
    Roots = { lighting, workspace, game:GetService("SoundService"), owner.hiddenVisuals },
    ExtraPolicy = function(object, target, watch, options)
      if owner.compatible then target, watch = applyGamePolicy(object, target, watch, options) end
      return applyScenePolicy(object, target, watch, options, owner.masks, owner.lobbyHidden, owner.lobby)
    end,
  }, owner.profile)
  local function getOption(key) return owner.engine:GetOption(key) end
  if owner.compatible then owner.adapter = createGameAdapter({ Workspace = workspace, Player = player, PlayerScripts = player:WaitForChild("PlayerScripts") }, getOption) end
  local collection = game:GetService("CollectionService")
  owner.occlusion = createOcclusionTester(
    workspace,
    function(part)
      return owner.engine:GetOriginalProperty(part, "LocalTransparencyModifier") < 0.99
        and not (owner.profile.HideTaggedDecorations and collection:HasTag(part, "AntiLagDecoration"))
    end
  )
  local function onHidden(object, hidden)
    owner.masks[object] = if hidden then true else nil
    if object:IsA("BasePart") then owner.engine:RefreshSubtree(object) else owner.engine:RefreshInstance(object) end
  end
  local playerScripts = player:WaitForChild("PlayerScripts")
  owner.relevance = createRelevanceController({
    Players = game:GetService("Players"),
    Player = player,
    Occlusion = owner.occlusion,
    OnHidden = onHidden,
  }, getOption)
  if owner.compatible then
    owner.scheduler = createVisualScheduler({
      Players = game:GetService("Players"),
      Player = player,
      PlayerScripts = playerScripts,
      RunService = runService,
      Relevance = owner.relevance,
    }, getOption)
  end
  owner.spatial = createSpatialController({
    Workspace = workspace,
    Player = player,
    RunService = runService,
    Occlusion = owner.occlusion,
    BeginFrame = function() owner.relevance:BeginFrame(os.clock(), workspace.CurrentCamera) end,
    OnHidden = onHidden,
    OnLobbyHidden = function(hidden, lobby)
      local previous = owner.lobby; owner.lobbyHidden, owner.lobby = hidden, lobby
      if previous then owner.engine:RefreshSubtree(previous) end
      if lobby and lobby ~= previous then owner.engine:RefreshSubtree(lobby) end
    end,
  }, getOption)
  owner.engine:SetEnabled(true)
  if owner.adapter then owner.adapter:SetEnabled(true) end
  owner.relevance:SetEnabled(true); owner.spatial:SetEnabled(true)
  if owner.scheduler then owner.scheduler:SetEnabled(true) end
  loadNativeModules(owner)
end
local function stopSession()
  local owner = session
  if not owner then return end
  owner.closed = true
  if owner.engine then owner.engine:SetEnabled(false) end
  if owner.scheduler then owner.scheduler:Destroy() end
  if owner.spatial then owner.spatial:Destroy() end
  if owner.relevance then owner.relevance:Destroy() end
  if owner.adapter then owner.adapter:Destroy() end
  if owner.engine then
    owner.engine:Destroy()
    while owner.engine:GetStatus().Alive do
      owner.runService.Heartbeat:Wait()
    end
  end
  if owner.hiddenVisuals and #owner.hiddenVisuals:GetChildren() == 0 then owner.hiddenVisuals:Destroy() end
  if session == owner then session = nil end
end
local function updateSession()
  local profile, owner = requestedProfile(), session; local spatialChanged = profile.CullDistance ~= owner.profile.CullDistance or profile.HideLobbyInMatch ~= owner.profile.HideLobbyInMatch
  for key, value in pairs(profile) do
    if owner.profile[key] ~= value then owner.engine:SetOption(key, value) end
  end
  owner.profile = profile
  if owner.adapter then owner.adapter:Refresh() end
  if owner.scheduler then owner.scheduler:Refresh() end
  if spatialChanged then owner.spatial:Refresh() end
end
local function reconcile()
  revision += 1
  if working then return end
  working = true
  task.defer(function()
    local seen
    repeat
      seen = revision
      local ok, err = pcall(function()
        if Utils and Utils.isActive() and setting("AntiLagEnabled") then
          if session then updateSession() else startSession() end
        else
          stopSession()
        end
      end)
      if not ok then
        local reporting = Utils; local cleaned, cleanupError = pcall(stopSession)
        if reporting then reporting.recordError("AntiLag", tostring(err)) end
        if not cleaned then warn("[Exodus AntiLag] Falha ao restaurar: " .. tostring(cleanupError)) end
      end
    until seen == revision
    working = false
  end)
end

-- public-api
function AntiLag.setEnabled(enabled)
  if not Utils then return false, "recurso indisponível" end
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
    characters = owner and owner.relevance and owner.relevance:GetStatus() or nil,
    scheduler = owner and owner.scheduler and owner.scheduler:GetStatus() or nil,
    occlusion = owner and owner.occlusion and owner.occlusion:GetStatus() or nil,
  }
end
function AntiLag.teardown()
  local previous = Utils; Utils = nil
  revision += 1
  if observer then observer:Disconnect(); observer = nil end
  if shutdown then
    shutdown.Connected = false
    if previous then previous.untrackGlobal(shutdown) end
    shutdown = nil
  end
  while working do
    game:GetService("RunService").Heartbeat:Wait()
  end
  stopSession(); return true
end
function AntiLag.setup(deps)
  if type(deps) ~= "table" or type(deps.Utils) ~= "table" then return false, "dependência ausente: Utils" end
  AntiLag.teardown(); Utils = deps.Utils
  observer = Utils.observeConfig(function(changes)
    for key in pairs(changes) do
      if CONFIG.schema[key] then
        if session or setting("AntiLagEnabled") then reconcile() end
        return
      end
    end
  end)
  shutdown = { Connected = true }
  function shutdown:Disconnect()
    if not self.Connected then return end
    self.Connected = false; AntiLag.teardown()
  end
  Utils.trackGlobal(shutdown)
  if setting("AntiLagEnabled") then reconcile() end
  return true
end
AntiLag.__config = CONFIG
AntiLag.__contract = {
  requires = { Utils = "utils" },
  requiresMethods = {
    Utils = { "getConfigValue", "setConfig", "getLocalPlayer", "isActive", "observeConfig", "trackGlobal", "untrackGlobal", "recordError" },
  },
  provides = { "setup", "teardown", "setEnabled", "getStatus" },
}

return AntiLag
