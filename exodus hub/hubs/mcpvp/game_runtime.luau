-- [[ gameruntime ]]
--!optimize 2
local Runtime = {}
local scope, modules
function Runtime.setup() return true end
function Runtime.reset()
  if not modules then
    return
  end
  modules.autostrength.reset()
  modules.autorefill.reset()
  modules.autototem.reset()
  modules.autopearl.reset()
  modules.autoattacksword.reset()
  modules.aimcontrol.reset()
  modules.mcptarget.reset()
end
function Runtime.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  Runtime.reset()
  modules = nil
end
function Runtime.bind(loaded)
  Runtime.teardown()
  modules = loaded
  loaded.autototem.setReservations(loaded.autorefill.isReserved)
  scope = loaded.lifetime.scope()
  local input = game:GetService("UserInputService")
  local controllerSource = game:GetService("ReplicatedStorage"):FindFirstChild("ControllerInput")
  local ok, controller = pcall(function() return controllerSource and require(controllerSource) end)
  if not ok then
    controller = nil
  end
  local function combatEnabled()
    return loaded.utils.getConfigValue("MCAutoSword")
      or loaded.utils.getConfigValue("MCAimLock")
      or loaded.utils.getConfigValue("MCAimAssist")
      or loaded.utils.getConfigValue("MCAutoPearl")
  end
  local function click(event, processed)
    if loaded.mcpnative.isDispatching() or processed or input:GetFocusedTextBox() or not loaded.utils.isActive() or not combatEnabled() then
      return
    end
    local matches = controller and type(controller.Matches) == "function" and controller.Matches(event, "Attack")
    if not matches and (controller or event.UserInputType ~= Enum.UserInputType.MouseButton1) then
      return
    end
    local snap = loaded.mcpnative.snapshot()
    if snap then
      loaded.mcptarget.manual(snap)
    end
  end
  scope.connect(controller and controller.InputBegan or input.InputBegan, click)
  local swingConnection, feedbackConnection
  local function bindSwing()
    if swingConnection and feedbackConnection then
      return
    end
    local combat = game:GetService("ReplicatedStorage"):FindFirstChild("VoxelCombat")
    local swing = combat and combat:FindFirstChild("Swing")
    if not swingConnection and swing and swing:IsA("RemoteEvent") then
      swingConnection = scope.connect(swing.OnClientEvent, loaded.mcptarget.noteSwing)
    end
    local feedback = combat and combat:FindFirstChild("Feedback")
    if not feedbackConnection and feedback and feedback:IsA("RemoteEvent") then
      feedbackConnection = scope.connect(feedback.OnClientEvent, function(kind, blocked)
        if kind == "HitConfirm" and not blocked then
          loaded.mcptarget.confirmHit(os.clock())
        end
      end)
    end
  end
  bindSwing()
  local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
  local item = remotes and remotes:FindFirstChild("ItemAction")
  if item and item:IsA("RemoteEvent") then
    scope.connect(item.OnClientEvent, function(...)
      if loaded.utils.isActive() and loaded.utils.getConfigValue("MCAutoPearl") then
        loaded.autopearl.observeProjectile(...)
      end
    end)
  end
  local function tick()
    if not loaded.utils.isActive() then
      Runtime.reset()
      return
    end
    if input:GetFocusedTextBox() or game:GetService("GuiService").MenuIsOpen then
      Runtime.reset()
      return
    end
    local snap = loaded.mcpnative.snapshot()
    if not snap then
      Runtime.reset()
      return
    end
    if not loaded.utils.getConfigValue("MCAutoSword") then
      loaded.autoattacksword.reset()
    end
    loaded.autorefill.observe(snap)
    -- Finish the owning transaction before another module can select a tool or open inventory.
    for _, transaction in ipairs({ loaded.autototem, loaded.autostrength, loaded.autorefill, loaded.autopearl }) do
      if transaction.busy() then
        transaction.step(snap)
        return
      end
    end
    for _, transaction in ipairs({ loaded.autototem, loaded.autostrength, loaded.autorefill }) do
      transaction.step(snap)
      if transaction.busy() then
        return
      end
    end
    if not combatEnabled() then
      loaded.autopearl.reset()
      loaded.autoattacksword.reset()
      loaded.aimcontrol.reset()
      loaded.mcptarget.reset()
      return
    end
    bindSwing()
    loaded.mcptarget.observe(snap)
    local target = loaded.mcptarget.get(snap)
    if loaded.utils.getConfigValue("MCAutoPearl") then
      loaded.autopearl.step(snap, target)
    else
      loaded.autopearl.reset()
    end
    if not target then
      loaded.autoattacksword.reset()
      loaded.aimcontrol.reset()
      return
    end
    if loaded.utils.getConfigValue("MCAutoSword") and not loaded.autopearl.busy() then
      loaded.autoattacksword.step(snap, target)
    end
  end
  scope.connect(game:GetService("RunService").Heartbeat, function()
    local success, reason = pcall(tick)
    if not success then
      Runtime.reset()
      loaded.utils.recordError("mcpvp.tick", tostring(reason))
    end
  end)
  scope.connect(game:GetService("RunService").RenderStepped, function(dt)
    if
      not loaded.utils.isActive()
      or not combatEnabled()
      or loaded.autopearl.busy()
      or loaded.autototem.busy()
      or loaded.autorefill.busy()
      or loaded.autostrength.busy()
    then
      loaded.aimcontrol.reset()
      return
    end
    local snap = loaded.mcpnative.snapshot()
    local target = snap and loaded.mcptarget.locked()
    if snap and target then
      loaded.aimcontrol.step(snap, target, dt)
    else
      loaded.aimcontrol.reset()
    end
  end)
  return { mode = "mcpvp" }
end
function Runtime.createAPI(loaded)
  return {
    getUIConfig = function() return loaded.gameui.definition end,
    resetState = Runtime.reset,
    updateBlockers = { loaded.autopearl.busy, loaded.autototem.busy, loaded.autorefill.busy, loaded.autostrength.busy },
  }
end
Runtime.__contract = {
  provides = { "setup", "reset", "teardown", "bind", "createAPI" },
  requires = {},
}
return Runtime
