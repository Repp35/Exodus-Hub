-- [[ gameruntime ]]
--!optimize 2
local Runtime = {}
local modules, scope, owner, renderTarget
function Runtime.setup() return true end
function Runtime.reset()
  if not modules then
    return
  end
  modules.autopearl.reset()
  modules.mcpmelee.reset()
  modules.mcpsupplies.reset()
  modules.mcptarget.reset()
  renderTarget = nil
end
function Runtime.teardown()
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
  local function guarded(name, fn, ...)
    local success, reason = pcall(fn, ...)
    if not success then
      Runtime.reset()
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
        target.manual(snap)
      end
    end)
  end)
  local bound, scanAt = {}, 0
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
    if snap.now >= scanAt then
      scanAt = snap.now + 1
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
    renderTarget = nil
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
    local chosen = target.get(snap)
    if enabled("MCAutoPearl") then
      loaded.autopearl.step(snap, chosen)
    else
      loaded.autopearl.reset()
    end
    if loaded.autopearl.busy() then
      loaded.mcpmelee.reset()
      return
    end
    renderTarget = chosen
    if chosen then
      loaded.mcpmelee.step(snap, chosen)
    else
      loaded.mcpmelee.reset()
    end
  end
  scope.connect(run.Heartbeat, function() guarded("heartbeat", heartbeat) end)
  scope.connect(run.RenderStepped, function(dt)
    guarded("aim", function()
      if
        not renderTarget
        or not renderTarget.root.Parent
        or renderTarget.humanoid.Health <= 0
        or not loaded.utils.isActive()
        or supplies.busy()
        or loaded.autopearl.busy()
      then
        return
      end
      local snap = native.snapshot()
      if snap then
        loaded.mcpaim.step(snap, renderTarget, dt)
      end
    end)
  end)
  return { mode = "mcpvp" }
end
function Runtime.createAPI(loaded)
  return {
    getUIConfig = function() return loaded.gameui.definition end,
    resetState = Runtime.reset,
    updateBlockers = { loaded.autopearl.busy, loaded.mcpsupplies.busy, loaded.mcpinventory.busy },
  }
end
Runtime.__contract = { provides = { "setup", "reset", "teardown", "bind", "createAPI" }, requires = {} }
return Runtime
