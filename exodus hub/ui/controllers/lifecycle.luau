-- [[ interface lifecycle ]]
--!optimize 2
-- @modules uilifecycle

local Controller = {}
function Controller.setup() return true end
function Controller.create(context)
  local controls, state = context.deps.Controls, context.state
  local retired = false
  local function restore(message)
    if not context.scope.alive then
      return
    end
    if context.notifications.toast then
      context.notifications.toast("Update failed. Check the console.", true)
    end
    warn("[Exodus Reload] " .. tostring(message))
  end
  local function fade()
    if retired or not context.scope.alive then
      return
    end
    retired, state.closing = true, true
    -- Visual copies finish independently while the live session releases all input and resources.
    local service = game:GetService("TweenService")
    local profile = context.theme.MOTION.panel
    for _, source in ipairs({ context.refs.screenGui, context.refs.informationGui }) do
      if source and source.Parent then
        local copy = source:Clone()
        copy.Name = "ExodusRetiringUI"
        local group = Instance.new("CanvasGroup")
        group.Size = UDim2.fromScale(1, 1)
        group.BackgroundTransparency = 1
        group.GroupTransparency = 0
        for _, child in ipairs(copy:GetChildren()) do
          child.Parent = group
        end
        group.Parent = copy
        for _, object in ipairs(copy:GetDescendants()) do
          if object:IsA("GuiObject") then
            object.Active, object.Selectable = false, false
          end
        end
        copy.Parent = source.Parent
        local tween = service:Create(group, TweenInfo.new(profile.duration, profile.style, profile.direction), {
          GroupTransparency = 1,
          Position = UDim2.fromOffset(0, 22),
        })
        tween:Play()
        task.delay(profile.duration, function() copy:Destroy() end)
      end
    end
  end
  local function animateClose(action)
    if state.closing then
      return
    end
    if action == "reload" then
      if controls.onReload then
        local ok, reason = controls.onReload(restore)
        if ok == false and context.notifications.toast then
          context.notifications.toast(tostring(reason), true)
        end
      end
      return
    end
    _G.ExodusShutdownReason = "close"
    if controls.onClose then
      controls.onClose()
    else
      context.deps.Utils.stop()
    end
  end
  return { restore = restore, fade = fade, animateClose = animateClose }
end
Controller.__contract = { provides = { "setup", "create" }, requires = {} }
return Controller
