-- [[ native visual and audio adaptation ]]
--!optimize 2

-- code
local Adapter = {}
function Adapter.setup() return true end
local function createGameAdapter(services, getOption)
  local adapter = {}
  local active, alive = false, true
  local modules = {}
  local patches, attributes = {}, {}
  local connections = {}
  local scheduled = false
  local refresh
  local stats = { DroppedVFX = 0, DroppedAudio = 0, RestoreConflicts = 0, Failures = 0 }
  local Workspace = services.Workspace
  local player = services.Player
  local audio, scan, audioDriver = {}, {}, nil
  local audioOwner = {}
  local function audioValue(object)
    if not active then
      return nil
    end
    if object:IsA("SoundGroup") and object.Parent and object.Parent.Name == "Master" then
      if
        object.Name == "Music" and getOption("GameMuteMusic")
        or object.Name == "Emotes" and getOption("GameCosmeticAudio")
        or object.Name == "Ambience" and getOption("GameMuteMusic")
      then
        return 0
      end
    elseif object:IsA("Sound") then
      local kind = object:GetAttribute("SFXKind")
      if
        getOption("GameSwordSounds") == false and (kind == "SwordSounds" or kind == "KillSounds")
        or object.Name == "PB_LobbyTheme_Christmas" and getOption("GameMuteMusic")
      then
        return 0
      end
    end
    return nil
  end
  local function restoreAudio(object)
    if audio[object] then
      services.Binding.release(audioOwner, object, "Volume")
      audio[object] = nil
    end
  end
  local function applyAudio(object)
    local desired = audioValue(object)
    if desired == nil then
      restoreAudio(object)
    else
      if services.Binding.apply(audioOwner, object, "Volume", desired, 100) then
        audio[object] = true
      end
    end
  end
  local function scanAudio(object)
    if not active or not alive or not services.Binding then
      return
    end
    scan[#scan + 1] = { items = { object }, index = 1 }
    if audioDriver then
      return
    end
    audioDriver = services.ConnectPhysics(function()
      local deadline, count = os.clock() + 0.0002, 0
      while #scan > 0 and count < 32 and os.clock() < deadline do
        local frame = scan[#scan]
        local current = frame.items[frame.index]
        if not current then
          scan[#scan] = nil
        else
          frame.index += 1
          count += 1
          if current.Parent then
            if current:IsA("Sound") or current:IsA("SoundGroup") then
              applyAudio(current)
            end
            local children = current:GetChildren()
            if #children > 0 then
              scan[#scan + 1] = { items = children, index = 1 }
            end
          end
        end
      end
      if #scan == 0 then
        audioDriver:Disconnect()
        audioDriver = nil
      end
    end)
  end
  local function enabledOption(key) return active and getOption(key) == true end
  local function deferRefresh()
    if scheduled or not alive then
      return
    end
    scheduled = true
    task.delay(0.25, function()
      scheduled = false
      if alive and active then
        refresh()
      end
    end)
  end
  local function reconcileAttribute(object, key, desired, wanted)
    local byKey = attributes[object]
    local saved = byKey and byKey[key]
    if not wanted then
      if saved then
        byKey[key] = nil
        if saved.connection then
          saved.connection:Disconnect()
        end
        local ok = pcall(function() object:SetAttribute(key, saved.original) end)
        if not ok then
          stats.Failures += 1
        end
        if next(byKey) == nil then
          attributes[object] = nil
        end
      end
      return
    end
    if not saved then
      local ok, original = pcall(function() return object:GetAttribute(key) end)
      if not ok then
        stats.Failures += 1
        return
      end
      if not byKey then
        byKey = {}
        attributes[object] = byKey
      end
      saved = { original = original, applied = desired }
      byKey[key] = saved
      saved.connection = object:GetAttributeChangedSignal(key):Connect(function()
        if not active or not alive then
          return
        end
        local value = object:GetAttribute(key)
        if value ~= saved.applied then
          if getOption("RestoreLatest") then
            saved.original = value
          end
          deferRefresh()
        end
      end)
    end
    saved.applied = desired
    local ok = pcall(function()
      if object:GetAttribute(key) ~= desired then
        object:SetAttribute(key, desired)
      end
    end)
    if not ok then
      stats.Failures += 1
    end
  end
  local function removePatch(id)
    local patch = patches[id]
    if not patch then
      return
    end
    patches[id] = nil
    if patch.object[patch.key] == patch.wrapper then
      local ok = pcall(function() patch.object[patch.key] = patch.original end)
      if not ok then
        stats.Failures += 1
      end
    else
      stats.RestoreConflicts += 1
    end
  end
  local function ensurePatch(moduleName, key, shouldBlock, category, replacement)
    local id = moduleName .. "." .. key
    local object = modules[moduleName]
    local wanted = active and getOption("GameGenerators") and type(object) == "table"
    if not wanted then
      removePatch(id)
      return
    end
    local existing = patches[id]
    if existing and existing.object == object and object[key] == existing.wrapper then
      return
    end
    if existing then
      removePatch(id)
    end
    local original = object[key]
    if type(original) ~= "function" then
      return
    end
    local wrapper = function(...)
      if alive and active and getOption("GameGenerators") and shouldBlock(...) then
        if category then
          stats[category] += 1
        end
        if replacement then
          return replacement(...)
        end
        return nil
      end
      return original(...)
    end
    local ok = pcall(function() object[key] = wrapper end)
    if ok then
      patches[id] = { object = object, key = key, original = original, wrapper = wrapper }
    else
      stats.Failures += 1
    end
  end
  refresh = function()
    if not alive then
      return
    end
    if not active then
      for object, byKey in pairs(attributes) do
        for key in pairs(byKey) do
          reconcileAttribute(object, key, nil, false)
        end
      end
    end
    if services.Binding then
      for object in pairs(audio) do
        applyAudio(object)
      end
      scanAudio(services.Workspace)
      scanAudio(services.SoundService)
    end
    local noVFX = enabledOption("GameNoVFX")
    local quiet = enabledOption("GameCosmeticAudio")
    local reducedUI = enabledOption("GameReducedUI")
    local flags = {
      PB_PerfEnabled = active,
      PB_PerfNoVFX = noVFX,
      PB_PerfReducedUI = reducedUI,
      PB_PerfMuteMusic = enabledOption("GameMuteMusic"),
      PB_PerfCosmeticAudio = quiet,
      PB_PerfKeepCombatAudio = getOption("GameKeepCombatAudio") == true,
      PB_PerfReducedHeadLook = enabledOption("GameReducedHeadLook"),
      PB_PerfSwordSounds = getOption("GameSwordSounds") ~= false,
    }

    for key, value in pairs(flags) do
      reconcileAttribute(Workspace, key, value, active)
    end
    reconcileAttribute(player, "Setting_WeaponVFX", false, noVFX)
    reconcileAttribute(player, "Setting_ExplosionVFX", false, noVFX)
    reconcileAttribute(player, "Setting_KillSounds", false, quiet or active and getOption("GameSwordSounds") == false)
    reconcileAttribute(player, "Setting_SwordSounds", false, active and getOption("GameSwordSounds") == false)
    for _, method in ipairs({ "Spawn", "SpawnAtCFrame", "SpawnSwordEffect", "Emit", "Toggle" }) do
      ensurePatch("VFX", method, function() return enabledOption("GameNoVFX") end, "DroppedVFX")
    end
    ensurePatch("LowQuality", "CanSpawn", function() return enabledOption("GameNoVFX") end, nil, function() return false end)
    ensurePatch("VFXBudget", "Take", function() return enabledOption("GameNoVFX") end, nil, function() return false end)
    ensurePatch("WindowAnim", "ReducedMotion", function() return enabledOption("GameReducedUI") end, nil, function() return true end)
    ensurePatch("SFX", "SpawnSwordSFX", function(_, _, action)
      if getOption("GameSwordSounds") == false then
        return true
      end
      if not enabledOption("GameCosmeticAudio") then
        return false
      end
      if getOption("GameKeepCombatAudio") and (action == "BallHit" or action == "Block") then
        return false
      end
      return true
    end, "DroppedAudio")
    local emitter = services.PlayerScripts and services.PlayerScripts:FindFirstChild("Emitter2D")
    local emitterModule = emitter and emitter:FindFirstChild("Emitter2D")
    if emitterModule and emitterModule:IsA("ModuleScript") then
      reconcileAttribute(emitterModule, "Enabled", false, reducedUI)
    end
  end
  function adapter:SetModule(name, value)
    if not alive or type(value) ~= "table" then
      return false
    end
    if modules[name] ~= value then
      local prefix = name .. "."
      for id in pairs(patches) do
        if id:sub(1, #prefix) == prefix then
          removePatch(id)
        end
      end
    end
    modules[name] = value
    if active then
      refresh()
    end
    return true
  end
  function adapter:SetEnabled(value)
    if not alive then
      return
    end
    active = value
    if not active then
      if audioDriver then
        audioDriver:Disconnect()
        audioDriver = nil
      end
      scan = {}
      for object in pairs(audio) do
        restoreAudio(object)
      end
    end
    refresh()
  end
  function adapter:Refresh()
    if active and alive then
      refresh()
    end
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
    if not alive then
      return
    end
    self:SetEnabled(false)
    alive = false
    for _, connection in ipairs(connections) do
      connection:Disconnect()
    end
  end
  local loading = setmetatable({}, { __mode = "k" })
  local specs = {
    { "VFX", "Core", "VFX" },
    { "SFX", "Core", "SFX" },
    { "LowQuality", "Core", "LowQuality" },
    { "VFXBudget", "Core" },
    { "WindowAnim", "UI" },
  }
  local function discover()
    if not alive then
      return
    end
    local replicated = services.ReplicatedStorage
    local shared = replicated and replicated:FindFirstChild("Shared")
    if not shared then
      return
    end
    for _, spec in ipairs(specs) do
      local branch = shared:FindFirstChild(spec[2])
      local script = branch and branch:FindFirstChild(spec[1])
      if script and script:IsA("ModuleScript") and not loading[script] then
        loading[script] = true
        services.Scope.defer(function()
          local ok, result = pcall(require, script)
          if alive and ok and type(result) == "table" then
            adapter:SetModule(spec[1], spec[3] and result[spec[3]] or result)
          end
        end)
      end
    end
  end
  if services.ReplicatedStorage then
    connections[#connections + 1] = services.ReplicatedStorage.DescendantAdded:Connect(function(object)
      if not object:IsA("ModuleScript") then
        return
      end
      for _, spec in ipairs(specs) do
        if object.Name == spec[1] then
          discover()
          break
        end
      end
    end)
  end
  if services.PlayerScripts then
    connections[#connections + 1] = services.PlayerScripts.DescendantAdded:Connect(function(object)
      if active and object.Name == "Emitter2D" then
        deferRefresh()
      end
    end)
  end
  if services.Binding then
    for _, root in ipairs({ services.Workspace, services.SoundService }) do
      connections[#connections + 1] = root.DescendantAdded:Connect(function(object)
        if object:IsA("Sound") or object:IsA("SoundGroup") then
          scanAudio(object)
        end
      end)
      connections[#connections + 1] = root.DescendantRemoving:Connect(restoreAudio)
    end
  end
  discover()
  return adapter
end
Adapter.create = createGameAdapter
Adapter.__contract = { requires = {}, provides = { "setup", "create" } }

return Adapter
