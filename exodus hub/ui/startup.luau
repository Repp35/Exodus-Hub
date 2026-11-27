-- [[ notification surface ]]
--!optimize 2
-- @modules uisurface

local Surface = {}
local Appearance
function Surface.setup(deps)
  Appearance = deps.Appearance
  return true
end
function Surface.create(appearance, options)
  appearance, options = appearance or Appearance, options or {}
  local service = game:GetService("TweenService")
  local entering = 0.32
  local function layer()
    local player = game:GetService("Players").LocalPlayer
    local parent = player and player:FindFirstChildOfClass("PlayerGui")
    if not parent then
      return nil
    end
    local gui = parent:FindFirstChild("ExodusPersistentNotifications")
    if not gui then
      gui = Instance.new("ScreenGui")
      gui.Name, gui.DisplayOrder = "ExodusPersistentNotifications", options.displayOrder or 2147483647
      gui.ResetOnSpawn, gui.IgnoreGuiInset = false, true
      gui.ZIndexBehavior, gui.Parent = Enum.ZIndexBehavior.Global, parent
    end
    local frame = gui:FindFirstChild("NotificationLayer")
    if not frame then
      frame = Instance.new("Frame")
      frame.Name, frame.Size, frame.BackgroundTransparency, frame.Parent = "NotificationLayer", UDim2.fromScale(1, 1), 1, gui
    end
    return frame
  end
  local function key(value) return tostring(value or "general"):gsub("[^%w_%-]", "_") end
  local function animate(card, goals, done)
    local tween = service:Create(card, TweenInfo.new(entering, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), goals)
    if done then
      tween.Completed:Once(function(status)
        if status == Enum.PlaybackState.Completed then
          done()
        end
      end)
    end
    tween:Play()
    return tween
  end
  local function reflow()
    local parent = layer()
    if not parent then
      return
    end
    local offset = 24
    for _, card in ipairs(parent:GetChildren()) do
      if card:IsA("CanvasGroup") and card:GetAttribute("ExodusNotificationKey") and not card:GetAttribute("ExodusNotificationExiting") then
        if card.GroupTransparency > 0 then
          card:SetAttribute("ExodusNotificationEnteredAt", os.clock() + entering)
        end
        animate(card, { Position = UDim2.new(0.5, 0, 1, -offset), GroupTransparency = 0 })
        offset += card.Size.Y.Offset + 8
      end
    end
  end
  local function clear(id)
    local parent = layer()
    local card = parent and parent:FindFirstChild("Notification_" .. key(id))
    if not card then
      return nil
    end
    local generation = (card:GetAttribute("ExodusNotificationGeneration") or 0) + 1
    card:SetAttribute("ExodusNotificationGeneration", generation)
    card:SetAttribute("ExodusNotificationExiting", true)
    return animate(card, { GroupTransparency = 1, Position = card.Position + UDim2.fromOffset(0, 12) }, function()
      if card.Parent and card:GetAttribute("ExodusNotificationGeneration") == generation then
        card:Destroy()
        reflow()
      end
    end)
  end
  local function show(message, id, kind, duration)
    local parent = layer()
    if not parent then
      return false
    end
    id = key(id)
    local card = parent:FindFirstChild("Notification_" .. id)
    if not card then
      card = appearance.notification(parent, "Notification_" .. id)
      card:SetAttribute("ExodusNotificationEnteredAt", os.clock() + entering)
    end
    card:SetAttribute("ExodusNotificationKey", id)
    card:SetAttribute("ExodusNotificationMessage", tostring(message))
    card:SetAttribute("ExodusNotificationKind", kind or "info")
    card:SetAttribute("ExodusNotificationExiting", false)
    local camera = workspace.CurrentCamera
    appearance.updateNotification(card, message, kind, camera and camera.ViewportSize or Vector2.new(1920, 1080))
    local generation = (card:GetAttribute("ExodusNotificationGeneration") or 0) + 1
    card:SetAttribute("ExodusNotificationGeneration", generation)
    card.Visible = true
    reflow()
    if duration == nil then
      duration = id == "dumper" and 0 or 2.5
    end
    if duration > 0 then
      task.delay(entering + duration, function()
        if card.Parent and card:GetAttribute("ExodusNotificationGeneration") == generation then
          clear(id)
        end
      end)
    end
    return true
  end
  local function finish(id)
    local parent = layer()
    local card = parent and parent:FindFirstChild("Notification_" .. key(id))
    if card then
      local remaining = (card:GetAttribute("ExodusNotificationEnteredAt") or 0) - os.clock()
      if remaining > 0 then
        task.wait(remaining)
      end
      local tween = clear(id)
      if tween then
        tween.Completed:Wait()
      end
    end
  end
  return { show = show, clear = clear, finish = finish, layer = layer }
end
Surface.__contract =
  { provides = { "setup", "create" }, requires = { Appearance = "uiappearance" }, requiresMethods = { Appearance = { "notification", "updateNotification" } } }
return Surface
