-- [[ gameruntime ]]
--!optimize 2
local Runtime = {}
local modules, scope, owner
function Runtime.setup() return true end
function Runtime.reset()
  if not modules then
    return
  end
  modules.autopearl.reset()
  modules.mcpmelee.reset()
  modules.mcpsupplies.reset()
  modules.mcptarget.reset()
  modules.mcpaim.reset()
end
function Runtime.teardown()
  if modules then
    modules.mcpnative.setAttackGate(nil)
  end
  if scope then
    scope.destroy()
    scope = nil
  end
  Runtime.reset()
  modules, owner = nil, nil
end
function Runtime.bind(loaded)
  Runtime.teardown()
  modules, scope = loaded, loaded.lifetime.scope()
  local native, target, supplies = loaded.mcpnative, loaded.mcptarget, loaded.mcpsupplies
  local function intercept(snap, direction)
    if owner ~= snap.character then
      Runtime.reset()
      owner = snap.character
    end
    return loaded.mcpmelee.intercept(snap, direction)
  end
  native.setAttackGate(intercept)
  local input, storage, run = game:GetService("UserInputService"), game:GetService("ReplicatedStorage"), game:GetService("RunService")
  local source = storage:FindFirstChild("ControllerInput")
  local ok, controller = pcall(function() return source and require(source) end)
  if not ok or type(controller) ~= "table" then
    controller = nil
  end
  local function enabled(key) return loaded.utils.getConfigValue(key) == true end
  local function combatEnabled()
    return enabled("MCAutoSword") or enabled("MCAutoCrit") or enabled("MCAutoPearl") or enabled("MCAimLock") or enabled("MCAimAssist")
  end
  local pearlRecoverAt = 0
  local function guarded(name, fn, ...)
    local success, reason = pcall(fn, ...)
    if not success then
      if name == "aim" then
        loaded.mcpaim.reset()
      elseif name == "critical" then
        loaded.mcpmelee.reset()
      elseif name == "pearl" then
        loaded.autopearl.reset()
        pearlRecoverAt = os.clock() + 0.5
      else
        Runtime.reset()
      end
      loaded.utils.recordError("mcpvp." .. name, tostring(reason))
    end
  end
  scope.connect(controller and controller.InputBegan or input.InputBegan, function(event, processed)
    guarded("input", function()
      if native.isDispatching() or processed or input:GetFocusedTextBox() or not loaded.utils.isActive() or not combatEnabled() then
        return
      end
      local matches = controller and type(controller.Matches) == "function" and controller.Matches(event, "Attack")
      if not matches and (controller or event.UserInputType ~= Enum.UserInputType.MouseButton1) then
        return
      end
      local snap = native.snapshot()
      if snap then
        if owner ~= snap.character then
          Runtime.reset()
          owner = snap.character
        end
        local chosen = target.manual(snap)
        if not native.attackGateReady() then
          loaded.mcpmelee.manual(snap, chosen)
        end
      end
    end)
  end)
  local bound, scanAt = {}, 0
  local protectionOwner, protectionConnections = nil, {}
  local function clearProtection()
    for _, connection in ipairs(protectionConnections) do
      connection:Disconnect()
    end
    protectionOwner, protectionConnections = nil, {}
  end
  scope.add(clearProtection)
  local function bindProtection(snap)
    if protectionOwner == snap.character then
      return
    end
    clearProtection()
    protectionOwner = snap.character
    for _, attribute in ipairs({ "OffhandItem", "TotemPoppedAt" }) do
      protectionConnections[#protectionConnections + 1] = snap.character:GetAttributeChangedSignal(attribute):Connect(function()
        guarded("totem", function()
          local current = loaded.utils.isActive() and native.snapshot()
          if current and current.character == protectionOwner then
            supplies.protect(current)
          end
        end)
      end)
    end
  end
  local function bindRemote(folderName, name, callback)
    local folder = storage:FindFirstChild(folderName)
    local remote = folder and folder:FindFirstChild(name)
    local previous = bound[name]
    if previous and previous.remote ~= remote then
      previous.connection:Disconnect()
      bound[name] = nil
    end
    if not remote or not remote:IsA("RemoteEvent") or bound[name] then
      return
    end
    bound[name] = { remote = remote, connection = scope.connect(remote.OnClientEvent, function(...) guarded(name, callback, ...) end) }
  end
  local function heartbeat()
    loaded.mcpinventory.step()
    if not loaded.utils.isActive() then
      if owner then
        Runtime.reset()
        owner = nil
      end
      return
    end
    local snap = native.snapshot()
    if not snap then
      if owner then
        Runtime.reset()
        owner = nil
      end
      return
    end
    if owner ~= snap.character then
      Runtime.reset()
      owner = snap.character
    end
    bindProtection(snap)
    if snap.now >= scanAt then
      scanAt = snap.now + 1
      native.setAttackGate(intercept)
      bindRemote("VoxelCombat", "Swing", target.noteSwing)
      bindRemote("VoxelCombat", "Feedback", function(kind, blocked)
        if kind == "HitConfirm" and not blocked then
          target.confirmHit(os.clock())
        end
      end)
      bindRemote("Remotes", "ItemAction", loaded.autopearl.observeProjectile)
    end
    target.observe(snap)
    supplies.observe(snap)
    supplies.step(snap, not loaded.autopearl.busy())
    if supplies.busy() then
      loaded.mcpmelee.reset()
      return
    end
    if not combatEnabled() then
      loaded.autopearl.reset()
      loaded.mcpmelee.reset()
      target.reset()
      return
    end
    snap = native.snapshot()
    if not snap then
      return
    end
    if enabled("MCAutoPearl") then
      if snap.now >= pearlRecoverAt then
        guarded("pearl", loaded.autopearl.step, snap, target.getPearl(snap))
      end
    else
      loaded.autopearl.reset()
    end
    if loaded.autopearl.busy() then
      loaded.mcpmelee.reset()
      return
    end
    snap = native.snapshot()
    if snap then
      loaded.mcpmelee.step(snap, target.get(snap))
    end
  end
  scope.connect(run.PreSimulation, function()
    guarded("critical", function()
      local snap = loaded.utils.isActive() and native.snapshot() or nil
      if snap then
        if owner ~= snap.character then
          Runtime.reset()
          owner = snap.character
        end
        bindProtection(snap)
        supplies.protect(snap)
      end
      loaded.mcpmelee.preSimulation(snap)
    end)
  end)
  scope.connect(run.PostSimulation, function()
    guarded("critical", function() loaded.mcpmelee.postSimulation(loaded.utils.isActive() and native.snapshot() or nil) end)
  end)
  scope.connect(run.Heartbeat, function() guarded("heartbeat", heartbeat) end)
  local renderScope = scope
  local renderName = "ExodusMCPAim_" .. tostring(renderScope)
  renderScope.add(function() run:UnbindFromRenderStep(renderName) end)
  run:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, function(dt)
    if not renderScope.alive then
      return
    end
    guarded("aim", function()
      if not loaded.utils.isActive() or not (enabled("MCAimLock") or enabled("MCAimAssist")) or supplies.busy() or loaded.autopearl.busy() then
        return
      end
      local snap = native.snapshot()
      if snap then
        local nearest = target.get(snap)
        loaded.mcpaim.step(snap, nearest, dt)
      end
    end)
  end)
  return { mode = "mcpvp" }
end
function Runtime.createAPI(loaded)
  return {
    getUIConfig = function() return loaded.gameui.definition end,
    resetState = Runtime.reset,
    updateBlockers = { loaded.autopearl.pending, loaded.mcpsupplies.busy, loaded.mcpinventory.busy },
    migrateConfig = loaded.mcpoptions.migrateConfig,
  }
end
Runtime.__contract = { provides = { "setup", "reset", "teardown", "bind", "createAPI" }, requires = {} }
return Runtime
