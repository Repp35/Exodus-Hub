-- [[ gameruntime ]]
--!optimize 2
local Runtime = {}
local scope, modules
function Runtime.setup() return true end
function Runtime.reset()
  if not modules then
    return
  end
  modules.autopearl.reset()
  modules.autoattacksword.reset()
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
  scope = loaded.lifetime.scope()
  local input = game:GetService("UserInputService")
  local controllerSource = game:GetService("ReplicatedStorage"):FindFirstChild("ControllerInput")
  local ok, controller = pcall(function() return controllerSource and require(controllerSource) end)
  if not ok then
    controller = nil
  end
  local function click(event, processed)
    if loaded.mcpnative.isDispatching() or processed or input:GetFocusedTextBox() or not loaded.utils.isActive() or not loaded.utils.getConfigValue("MCAutoSword") then
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
    if swingConnection and feedbackConnection then return end
    local combat = game:GetService("ReplicatedStorage"):FindFirstChild("VoxelCombat")
    local swing = combat and combat:FindFirstChild("Swing")
    if not swingConnection and swing and swing:IsA("RemoteEvent") then
      swingConnection = scope.connect(swing.OnClientEvent, loaded.mcptarget.noteSwing)
    end
    local feedback = combat and combat:FindFirstChild("Feedback")
    if not feedbackConnection and feedback and feedback:IsA("RemoteEvent") then
      feedbackConnection = scope.connect(feedback.OnClientEvent, function(kind, blocked)
        if kind == "HitConfirm" and not blocked then loaded.mcptarget.confirmHit(os.clock()) end
      end)
    end
  end
  bindSwing()
  scope.connect(game:GetService("RunService").Heartbeat, function()
    if not loaded.utils.isActive() or not loaded.utils.getConfigValue("MCAutoSword") then
      Runtime.reset()
      return
    end
    local snap = loaded.mcpnative.snapshot()
    if not snap then
      Runtime.reset()
      return
    end
    bindSwing()
    loaded.mcptarget.observe(snap)
    local target = loaded.mcptarget.get(snap)
    if not target then
      loaded.autopearl.reset()
      return
    end
    local success, reason = pcall(function()
      if loaded.utils.getConfigValue("MCAutoPearl") then
        loaded.autopearl.step(snap, target)
      else
        loaded.autopearl.reset()
      end
      if not loaded.autopearl.busy() then
        local fresh = loaded.mcpnative.snapshot()
        local activeTarget = fresh and loaded.mcptarget.get(fresh)
        if fresh and activeTarget then loaded.autoattacksword.step(fresh, activeTarget) end
      end
    end)
    if not success then
      Runtime.reset()
      loaded.utils.recordError("mcpvp.combat", tostring(reason))
    end
  end)
  scope.connect(game:GetService("RunService").RenderStepped, function(dt)
    if not loaded.utils.isActive() or not loaded.utils.getConfigValue("MCAutoSword") or loaded.autopearl.busy() then
      return
    end
    local snap = loaded.mcpnative.snapshot()
    local target = snap and loaded.mcptarget.get(snap)
    if target then
      loaded.autoattacksword.aim(snap, target, dt)
    end
  end)
  return { mode = "mcpvp" }
end
function Runtime.createAPI(loaded)
  return { getUIConfig = function() return loaded.gameui.definition end, resetState = Runtime.reset, updateBlockers = { loaded.autopearl.busy } }
end
Runtime.__contract = {
  provides = { "setup", "reset", "teardown", "bind", "createAPI" },
  requires = {},
}
return Runtime
