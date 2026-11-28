-- [[ gameruntime ]]
--!optimize 2
local Runtime = {}
local modules, scope, owner
function Runtime.setup() return true end
function Runtime.reset()
  if not modules then
    return
  end
  modules.mcpmelee.reset()
  modules.autopearl.reset()
  modules.mcptarget.reset()
  modules.mcpaim.reset()
  modules.mcpsurvival.reset()
end
function Runtime.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  if modules then
    Runtime.reset()
    modules.mcpsupplies.reset()
    modules.mcpnative.teardown()
  end
  modules, owner = nil, nil
end
function Runtime.bind(loaded)
  Runtime.teardown()
  modules, scope = loaded, loaded.lifetime.scope()
  local native, target, melee, pearl, supplies, aim, survival =
    loaded.mcpnative, loaded.mcptarget, loaded.mcpmelee, loaded.autopearl, loaded.mcpsupplies, loaded.mcpaim, loaded.mcpsurvival
  local function run(name, fn, ...)
    local ok, reason = pcall(fn, ...)
    if not ok then
      if name == "pearl" then
        pearl.reset()
      elseif name == "melee" then
        melee.reset()
      elseif name == "aim" then
        aim.reset()
      else
        Runtime.reset()
        supplies.reset()
      end
      loaded.utils.recordError("mcpvp." .. name, tostring(reason))
    end
  end
  local characterScope
  local function synchronize(snap)
    if owner == snap.character then
      return
    end
    Runtime.reset()
    supplies.reset()
    native.reset()
    owner = snap.character
    if characterScope then
      characterScope.destroy()
    end
    characterScope = loaded.lifetime.scope()
    for _, attribute in ipairs({ "OffhandItem", "TotemPoppedAt" }) do
      characterScope.connect(owner:GetAttributeChangedSignal(attribute), function()
        run("supplies", function()
          local current = loaded.utils.isActive() and native.snapshot()
          if current and current.character == owner then
            supplies.step(current, not pearl.busy() and not survival.busy())
          end
        end)
      end)
    end
  end
  scope.add(function()
    if characterScope then
      characterScope.destroy()
      characterScope = nil
    end
  end)
  local function snapshot()
    if not loaded.utils.isActive() then
      return nil
    end
    local snap = native.snapshot()
    if snap then
      synchronize(snap)
    end
    return snap
  end
  local controller, inputScope
  local nextInputScan = 0
  local input = game:GetService("UserInputService")
  local function gate(snap, direction)
    if not loaded.utils.isActive() then
      return true
    end
    if survival.busy() or pearl.busy() or supplies.busy() then
      -- Item automation must never swallow the player's own native input.
      return true
    end
    if native.blocked(snap) then
      return true
    end
    synchronize(snap)
    local chosen
    if controller and controller.IsHeld("Attack") then
      chosen = target.manual(snap, direction)
    else
      chosen = target.near(snap)
      direction = direction or snap.player:GetAttribute("FrontCameraAimDirection") or snap.camera.CFrame.LookVector
      if chosen and not loaded.mcpgeometry.hit(snap, chosen, snap.tool, direction) then
        chosen = nil
      end
    end
    return not melee.request(snap, chosen)
  end
  local warned = false
  local function onInput(event, processed)
    run("input", function()
      if processed or native.isDispatching() or input:GetFocusedTextBox() then
        return
      end
      local attack = controller and controller.Matches(event, "Attack") or not controller and event.UserInputType == Enum.UserInputType.MouseButton1
      if not attack then
        return
      end
      local snap = snapshot()
      if not snap then
        return
      end
      target.manual(snap)
      if loaded.utils.getConfigValue("MCAutoCrit") and not warned then
        local ready, reason = native.gate(gate)
        if not ready and reason then
          warned = true
          loaded.utils.recordError("mcpvp.manual", reason)
        end
      end
    end)
  end
  local function synchronizeInput()
    if os.clock() < nextInputScan then
      return
    end
    nextInputScan = os.clock() + 0.5
    local source = game:GetService("ReplicatedStorage"):FindFirstChild("ControllerInput")
    local value = source and require(source)
    if
      type(value) ~= "table"
      or not value.InputBegan
      or type(value.BeginTouch) ~= "function"
      or type(value.Matches) ~= "function"
      or type(value.IsHeld) ~= "function"
    then
      value = nil
    end
    if inputScope and controller == value then
      return
    end
    if inputScope then
      inputScope.destroy()
    end
    controller, inputScope = value, scope.child()
    if controller then
      local current, lifetime = controller, inputScope
      local original = current.BeginTouch
      local function begin(action)
        if lifetime.alive and action == "Attack" and not native.isDispatching() then
          run("input", function()
            local snap = snapshot()
            if snap then
              target.manual(snap)
            end
          end)
        end
        return original(action)
      end
      current.BeginTouch = begin
      lifetime.add(function()
        if current.BeginTouch == begin then
          current.BeginTouch = original
        end
      end)
    end
    inputScope.connect(controller and controller.InputBegan or input.InputBegan, onInput)
  end
  run("input", synchronizeInput)
  local remotes, scanAt = {}, 0
  local function bindRemote(folderName, name, callback)
    local folder = game:GetService("ReplicatedStorage"):FindFirstChild(folderName)
    local remote = folder and folder:FindFirstChild(name)
    local old = remotes[name]
    if old and old.remote == remote then
      return
    end
    if old then
      old.connection:Disconnect()
      remotes[name] = nil
    end
    if remote and remote:IsA("RemoteEvent") then
      remotes[name] = { remote = remote, connection = scope.connect(remote.OnClientEvent, function(...) run(name, callback, ...) end) }
    end
  end
  native.gate(gate)
  local service = game:GetService("RunService")
  scope.connect(service.PreSimulation, function()
    run("frame", function()
      synchronizeInput()
      local snap = snapshot()
      if not snap then
        if owner then
          Runtime.reset()
          supplies.reset()
          owner = nil
        end
        return
      end
      if snap.now >= scanAt then
        scanAt = snap.now + 1
        native.gate(gate)
        bindRemote("VoxelCombat", "Swing", target.noteSwing)
        bindRemote("VoxelCombat", "Feedback", function(kind, blocked)
          if kind == "HitConfirm" and not blocked then
            target.hit(os.clock())
          end
        end)
        bindRemote("Remotes", "ItemAction", pearl.projectile)
      end
      target.observe(snap)
      if pearl.observe(snap) then
        snap = native.snapshot()
        if not snap then
          return
        end
      end
      local surviving = survival.step(snap, not supplies.busy() and not native.busy())
      supplies.step(snap, not pearl.busy() and not surviving)
      if surviving or supplies.busy() or native.blocked(snap) then
        melee.reset()
        return
      end
      run("pearl", pearl.prepare, snap)
      if pearl.busy() or native.busy() then
        melee.reset()
        return
      end
      snap = native.snapshot()
      if snap then
        run("melee", melee.prepare, snap)
      end
    end)
  end)
  scope.connect(service.PostSimulation, function()
    run("melee", function()
      local snap = snapshot()
      if not snap or survival.busy() or supplies.busy() or pearl.busy() or native.busy() then
        return
      end
      melee.strike(snap)
    end)
  end)
  local binding = "ExodusMCPAim_" .. tostring(scope)
  scope.add(function() service:UnbindFromRenderStep(binding) end)
  service:BindToRenderStep(binding, Enum.RenderPriority.Camera.Value + 1, function(dt)
    loaded.mcpinventory.present()
    run("aim", function()
      local snap = snapshot()
      if snap then
        target.observeView(snap)
        survival.move(snap)
        if not supplies.busy() and not native.blocked(snap) then
          local aimingPearl = pearl.aim(snap, dt)
          if not aimingPearl and not pearl.busy() and not survival.busy() then
            aim.step(snap, target.near(snap), dt)
          end
        end
        aim.observe(snap)
      end
    end)
  end)
  return { mode = "mcpvp" }
end
function Runtime.createAPI(loaded)
  return {
    getUIConfig = function() return loaded.gameui.definition end,
    resetState = Runtime.reset,
    controls = {
      onStopPvP = Runtime.reset,
      onThrowPearl = function()
        local snap = loaded.utils.isActive() and loaded.mcpnative.snapshot()
        if not snap then
          return false
        end
        if loaded.mcpsupplies.busy() or loaded.mcpsurvival.busy() or loaded.mcpnative.blocked(snap) then
          return false
        end
        return loaded.autopearl.throw(snap)
      end,
    },
    updateBlockers = { loaded.autopearl.pending, loaded.mcpsupplies.busy, loaded.mcpsurvival.busy, loaded.mcpnative.busy },
    migrateConfig = loaded.mcpoptions.migrateConfig,
  }
end
Runtime.__contract = { provides = { "setup", "reset", "teardown", "bind", "createAPI" }, requires = {} }
return Runtime
