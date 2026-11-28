-- [[ properties ]]
--!optimize 2
-- @modules renderproperties

-- code
local Properties = {}
local shared
function Properties.setup(deps)
  shared = deps.Binding
  return true
end
local function createOptimizer(services, initialConfig)
  local Workspace = services.Workspace
  local Lighting = services.Lighting
  local roots = services.Roots or { Workspace, Lighting }
  local CollectionService = services.CollectionService
  local options = table.clone(initialConfig)
  local controller = {}
  local enabled, alive, destroying = false, true, false
  local journal, records = {}, {}
  local connections = {}
  local pending, queued, head, tail = {}, {}, 1, 0
  local scan = {}
  local dirty = {}
  local delayed = false
  local workerRunning = false
  local driver
  local generation = 0
  local unsupported = {}
  local unsupportedCount, restoreFailures, runtimeFailures = 0, 0, 0
  local changedProperties = 0
  local scheduleWorker, enqueue, process, restartScan
  local oneSequence = NumberSequence.new(1)
  local zeroLifetime = NumberRange.new(0)
  local white, black = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
  local skyProperties = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }
  local function read(object, property)
    return pcall(function() return object[property] end)
  end
  local function reportUnavailable(key)
    if not unsupported[key] then
      unsupported[key] = true
      unsupportedCount += 1
      if key ~= "Terrain.Decoration" then
        warn("[AntiLag] Ajuste indisponivel neste cliente: " .. key)
      end
    end
  end
  local function unavailable(object, property) reportUnavailable(object.ClassName .. "." .. property) end
  local function inScope(object)
    for _, root in ipairs(roots) do
      if object == root or object:IsDescendantOf(root) then
        return true
      end
    end
    return false
  end
  local function desiredFor(object)
    local target = {}
    local watch = true
    if object == services.GameSettings then
      if options.LowestGraphics then
        target.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
      end
      return target, false
    elseif object == Lighting then
      if options.Shadows then
        target.GlobalShadows = false
      end
      if options.FlatLighting then
        target.Ambient, target.OutdoorAmbient = white, white
        target.Brightness, target.ExposureCompensation = 0, 0
        target.EnvironmentDiffuseScale, target.EnvironmentSpecularScale = 0, 0
        target.ColorShift_Top, target.ColorShift_Bottom = black, black
        local ok, soft = pcall(function() return Enum.LightingStyle.Soft end)
        if ok then
          target.LightingStyle = soft
        end
        target.PrioritizeLightingQuality = false
      end
      if options.NoFog then
        target.FogStart, target.FogEnd = 0, 1000000
      end
    elseif object:IsA("Terrain") then
      if options.Water then
        target.WaterWaveSize, target.WaterWaveSpeed, target.WaterReflectance = 0, 0, 0
        target.WaterTransparency = if options.TransparentWater then 1 else 0
      end
      if options.TerrainDecoration then
        target.Decoration = false
      end
    elseif object:IsA("ParticleEmitter") then
      if options.Particles then
        target.Enabled = false
        target.Lifetime = zeroLifetime
        target.Transparency = oneSequence
        target.LocalTransparencyModifier = 1
      end
    elseif object:IsA("Trail") or object:IsA("Beam") then
      if options.TrailsAndBeams then
        target.Enabled, target.Transparency = false, oneSequence
      end
    elseif object:IsA("Smoke") then
      if options.LegacyEffects then
        target.Enabled, target.Opacity, target.LocalTransparencyModifier = false, 0, 1
      end
    elseif object:IsA("Fire") then
      if options.LegacyEffects then
        target.Enabled, target.LocalTransparencyModifier = false, 1
      end
    elseif object:IsA("Sparkles") then
      if options.LegacyEffects then
        target.Enabled, target.LocalTransparencyModifier = false, 1
      end
    elseif object:IsA("Highlight") then
      if options.LegacyEffects and object:GetAttribute("UIComponent") ~= true then
        target.Enabled = false
      end
    elseif object:IsA("ForceField") or object:IsA("Explosion") then
      if options.LegacyEffects then
        target.Visible = false
      end
    elseif object:IsA("PostEffect") then
      if options.PostEffects then
        target.Enabled = false
      end
    elseif object:IsA("Light") then
      if options.Lights then
        target.Enabled = false
      end
      if options.Shadows then
        target.Shadows = false
      end
    elseif object:IsA("Atmosphere") then
      if options.Atmosphere then
        target.Density, target.Haze, target.Glare = 0, 0, 0
      end
    elseif object:IsA("Clouds") then
      if options.Clouds then
        target.Enabled = false
      end
    elseif object:IsA("Sky") then
      if options.FlatSky then
        target.CelestialBodiesShown, target.StarCount = false, 0
        if options.RemoveTextures then
          for _, property in ipairs(skyProperties) do
            target[property] = options.FlatSkyTexture
          end
        end
      end
    elseif object:IsA("Decal") or object:IsA("Texture") then
      if options.RemoveTextures then
        target.Transparency = 1
      end
    elseif object:IsA("SpecialMesh") then
      if options.RemoveTextures then
        target.TextureId = ""
      end
    elseif object:IsA("SurfaceAppearance") then
      if options.RemoveTextures then
        target.ColorMap, target.NormalMap, target.MetalnessMap, target.RoughnessMap = "", "", "", ""
      end
    elseif object:IsA("BasePart") then
      watch = false
      if object:IsA("MeshPart") then
        if options.RemoveTextures then
          target.TextureID = ""
        end
      end
      if options.Shadows then
        target.CastShadow = false
      end
      if options.FlatMaterials then
        target.Material = Enum.Material.SmoothPlastic
        target.MaterialVariant, target.Reflectance = "", 0
      end
      if options.HideTaggedDecorations and CollectionService:HasTag(object, "AntiLagDecoration") then
        target.LocalTransparencyModifier = 1
      end
    end
    return target, watch and options.MaintainEffects
  end
  local function removeEntry(entry)
    if entry.connection then
      entry.connection:Disconnect()
      entry.connection = nil
    end
    journal[entry.object] = nil
    local index = entry.index
    local last = records[#records]
    records[index] = last
    if last then
      last.index = index
    end
    records[#records] = nil
  end
  local function restoreProperty(object, property, saved)
    if not shared.release(saved, object, property) then
      restoreFailures += 1
    end
  end
  local function restoreEntry(entry)
    removeEntry(entry)
    for property, saved in pairs(entry.properties) do
      restoreProperty(entry.object, property, saved)
      changedProperties -= 1
    end
  end
  local function delayDirty()
    if delayed then
      return
    end
    delayed = true
    task.delay(options.ReapplyInterval, function()
      delayed = false
      local batch = dirty
      dirty = {}
      if not alive or not enabled then
        return
      end
      for object in pairs(batch) do
        enqueue(object)
      end
    end)
  end
  local function updateWatcher(entry, watch)
    if not watch then
      if entry.connection then
        entry.connection:Disconnect()
        entry.connection = nil
      end
      return
    end
    if entry.connection then
      return
    end
    entry.connection = entry.object.Changed:Connect(function(property)
      if not enabled or not alive or journal[entry.object] ~= entry then
        return
      end
      local saved = entry.properties[property]
      if not saved then
        return
      end
      local ok, current = read(entry.object, property)
      if not ok or current == saved.applied then
        return
      end
      if options.RestoreLatest then
        saved.original = current
      end
      dirty[entry.object] = true
      delayDirty()
    end)
  end
  process = function(object)
    local special = object == services.GameSettings
    if not enabled or (not special and not inScope(object)) then
      if journal[object] then
        restoreEntry(journal[object])
      end
      return
    end
    local target, watch = desiredFor(object)
    if services.ExtraPolicy then
      target, watch = services.ExtraPolicy(object, target, watch, options)
    end
    local entry = journal[object]
    if entry then
      for property, saved in pairs(entry.properties) do
        if target[property] == nil then
          entry.properties[property] = nil
          restoreProperty(object, property, saved)
          changedProperties -= 1
        end
      end
    end
    for property, value in pairs(target) do
      if unsupported[object.ClassName .. "." .. property] then
        continue
      end
      local ok, current = read(object, property)
      if not ok then
        unavailable(object, property)
        continue
      end
      local saved = entry and entry.properties[property]
      if not saved and current == value and not watch then
        continue
      end
      if not entry then
        entry = { object = object, properties = {}, index = #records + 1 }
        journal[object], records[entry.index] = entry, entry
      end
      if not saved then
        saved = { original = current, applied = current }
        entry.properties[property] = saved
        changedProperties += 1
      elseif options.RestoreLatest and current ~= saved.applied then
        saved.original = current
      end
      if current ~= value then
        local previous = saved.applied
        saved.applied = value
        if not shared.apply(saved, object, property, value, 100) then
          saved.applied = previous
          unavailable(object, property)
          if saved.original == current then
            shared.release(saved, object, property)
            entry.properties[property] = nil
            changedProperties -= 1
          end
        end
      else
        shared.apply(saved, object, property, value, 100)
        saved.applied = value
      end
    end
    if entry then
      if next(entry.properties) == nil then
        removeEntry(entry)
      else
        updateWatcher(entry, watch)
      end
    end
  end
  local function popPending()
    if head > tail then
      return nil
    end
    local object = pending[head]
    pending[head] = nil
    head += 1
    queued[object] = nil
    if head > tail then
      pending, head, tail = {}, 1, 0
    end
    return object
  end
  local function nextScan()
    while #scan > 0 do
      local frame = scan[#scan]
      local object = frame.items[frame.index]
      if not object then
        scan[#scan] = nil
        continue
      end
      frame.index += 1
      local ok, children = pcall(function() return object:GetChildren() end)
      if ok and #children > 0 then
        scan[#scan + 1] = { items = children, index = 1 }
      end
      return object
    end
    return nil
  end
  local function workAvailable() return if enabled then head <= tail or #scan > 0 else #records > 0 end
  local function finishDestroy()
    alive = false
    if driver then
      driver:Disconnect()
      driver = nil
    end
    workerRunning = false
    for _, connection in ipairs(connections) do
      connection:Disconnect()
    end
    connections, dirty, pending, queued, scan = {}, {}, {}, {}, {}
  end
  local function disconnectDriver()
    if driver then
      driver:Disconnect()
      driver = nil
    end
    workerRunning = false
  end
  local function work()
    if not alive then
      disconnectDriver()
      return
    end
    local phases = services.PhasesPerFrame or 2
    local deadline = os.clock() + options.BudgetMs / (1000 * phases)
    local limit = math.max(1, math.floor(options.MaxItemsPerFrame / phases))
    for count = 1, limit do
      if not workAvailable() or os.clock() >= deadline then
        break
      end
      if not enabled then
        restoreEntry(records[#records])
      else
        local object
        if count % 2 == 0 then
          object = popPending() or nextScan()
        else
          object = nextScan() or popPending()
        end
        if object then
          local ok, message = pcall(process, object)
          if not ok then
            runtimeFailures += 1
            if runtimeFailures <= 3 then
              warn("[AntiLag] " .. tostring(message))
            end
          end
        end
      end
    end
    if not workAvailable() then
      disconnectDriver()
      if destroying and not enabled then
        finishDestroy()
      end
    end
  end
  scheduleWorker = function()
    if workerRunning or not alive then
      return
    end
    workerRunning = true
    driver = services.ConnectPhysics(work)
  end
  enqueue = function(object)
    if not alive or not enabled or queued[object] then
      return
    end
    tail += 1
    pending[tail], queued[object] = object, true
    scheduleWorker()
  end
  restartScan = function()
    generation += 1
    scan = { { items = table.clone(roots), index = 1 } }
    if services.GameSettings then
      enqueue(services.GameSettings)
    end
    if options.LowestGraphics and not services.GameSettings then
      reportUnavailable("UserGameSettings.SavedQualityLevel")
    end
    if enabled then
      process(Lighting)
      if services.GameSettings then
        process(services.GameSettings)
      end
    end
    scheduleWorker()
  end
  for _, root in ipairs(roots) do
    connections[#connections + 1] = root.DescendantAdded:Connect(enqueue)
    connections[#connections + 1] = root.DescendantRemoving:Connect(function(object)
      if journal[object] then
        enqueue(object)
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
    if enabled and object:IsA("Humanoid") and object.Parent then
      scan[#scan + 1] = { items = { object.Parent }, index = 1 }
      scheduleWorker()
    end
  end)
  function controller:RefreshInstance(object, immediate)
    if not enabled or not alive then
      return
    end
    if immediate then
      local ok, message = pcall(process, object)
      if not ok then
        runtimeFailures += 1
        if runtimeFailures <= 3 then
          warn("[AntiLag] " .. tostring(message))
        end
      end
    else
      enqueue(object)
    end
  end
  function controller:RefreshSubtree(object)
    if enabled and alive and object then
      scan[#scan + 1] = { items = { object }, index = 1 }
      scheduleWorker()
    end
  end
  function controller:SetEnabled(value)
    if not alive or destroying or enabled == value then
      return
    end
    enabled = value
    generation += 1
    if enabled then
      restartScan()
    else
      pending, queued, scan, dirty, head, tail = {}, {}, {}, {}, 1, 0
      scheduleWorker()
    end
  end
  local batching = false
  local needsScan = false
  function controller:SetOption(key, value)
    if not alive or destroying or options[key] == nil then
      return false
    end
    if typeof(value) ~= typeof(options[key]) then
      return false
    end
    if type(value) == "number" and (value ~= value or math.abs(value) == math.huge) then
      return false
    end
    if key == "BudgetMs" then
      value = math.clamp(value, 0.25, 4)
    end
    if key == "MaxItemsPerFrame" then
      value = math.floor(math.clamp(value, 8, 1000))
    end
    if key == "ReapplyInterval" then
      value = math.clamp(value, 0.1, 2)
    end
    local bounds = {
      CullDistance = { 128, 6000 },
      CullKeepNear = { 64, 512 },
      CullViewPadding = { 0, 100 },
      CullViewDegrees = { 2, 30 },
      CullHideDelay = { 0.05, 2 },
      CullInterval = { 0.06, 0.35 },
      CullBudgetMs = { 0.2, 1.5 },
      CullAbove = { 80, 600 },
      CullBelow = { 50, 400 },
      CullVerticalMargin = { 5, 30 },
    }

    if bounds[key] then
      value = math.clamp(value, bounds[key][1], bounds[key][2])
    end
    if options[key] == value then
      return true
    end
    options[key] = value
    local noScan = key == "ShowFPS"
      or key == "ShowMenu"
      or key == "StartEnabled"
      or key == "BudgetMs"
      or key == "MaxItemsPerFrame"
      or key == "ReapplyInterval"
      or key == "RestoreLatest"
      or string.sub(key, 1, 4) == "Cull"
      or key == "HideLobbyInMatch"
    if enabled and not noScan then
      if batching then
        needsScan = true
      else
        restartScan()
      end
    end
    return true
  end
  function controller:SetOptions(values)
    batching = true
    local accepted = true
    for key, value in pairs(values) do
      if not self:SetOption(key, value) then
        accepted = false
      end
    end
    batching = false
    if needsScan then
      needsScan = false
      restartScan()
    end
    return accepted
  end
  function controller:GetOption(key) return options[key] end
  function controller:GetStatus()
    return {
      Enabled = enabled,
      Alive = alive,
      Destroying = destroying,
      Busy = workerRunning or workAvailable(),
      Instances = #records,
      Properties = changedProperties,
      Unsupported = unsupportedCount,
      UnsupportedProperties = table.clone(unsupported),
      RestoreFailures = restoreFailures,
      RuntimeFailures = runtimeFailures,
      Generation = generation,
    }
  end
  function controller:Destroy()
    if not alive or destroying then
      return
    end
    self:SetEnabled(false)
    destroying = true
    if #records == 0 then
      finishDestroy()
    else
      scheduleWorker()
    end
  end
  for _, key in ipairs({ "BudgetMs", "MaxItemsPerFrame", "ReapplyInterval" }) do
    controller:SetOption(key, options[key])
  end
  controller:SetEnabled(options.StartEnabled)
  return controller
end
Properties.create = createOptimizer
Properties.__contract = {
  access = { default = "render.write" },
  requires = { Binding = "propertybinding" },
  requiresMethods = { Binding = { "apply", "release" } },
  provides = { "setup", "create" },
}

return Properties
