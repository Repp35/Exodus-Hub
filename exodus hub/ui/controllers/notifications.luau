-- [[ notifications ]]
--!optimize 2
-- @modules uinotifications, uinotificationview

-- code
local __part_uinotifications = (function()
  local Notifications = {}
  local CONFIG = { SILENT_TOPICS = { manualSpam = true, upDash = true } }
  function Notifications.setup() return true end
  function Notifications.shouldShow(config, desktop, event)
    event = event or {}
    if event.category == "critical" or event.category == "lifecycle" then
      return true
    end
    if event.topic and CONFIG.SILENT_TOPICS[event.topic] then
      return false
    end
    local enabled = config[desktop and "DesktopNotifications" or "MobileNotifications"] == true
    if not enabled then
      return false
    end
    if event.category == "system" then
      return true
    end
    return desktop and event.category == "shortcut" and config.DesktopShortcutNotifications == true
  end
  Notifications.__contract = { provides = { "setup", "shouldShow" }, requires = {} }
  return Notifications
end)()
local __part_uinotificationview = (function()
  local Controller = {}

  function Controller.setup() return true end
  function Controller.create(context)
    local Utils, UIState = context.deps.Utils, context.state
    local scope = context.scope.child()
    local Appearance, Policy = context.deps.Appearance, context.deps.NotificationPolicy
    local state = { order = {}, tweens = {}, timers = {} }
    local layerMount
    local disposed = false
    scope.add(function()
      disposed = true
      for _, tween in pairs(state.tweens) do
        context.safeCancel(tween)
      end
      for _, timer in pairs(state.timers) do
        pcall(task.cancel, timer)
      end
      if state.gui then
        state.gui:Destroy()
      end
      state.gui, state.layer = nil, nil
      table.clear(state.order)
      table.clear(state.tweens)
      table.clear(state.timers)
    end)
    local function key(value) return tostring(value or "general"):gsub("[^%w_%-]", "_") end
    local function layer()
      if disposed or not scope.alive then
        return nil
      end
      local player = context.services.Players.LocalPlayer
      local parent = player and player:FindFirstChildOfClass("PlayerGui")
      if not parent then
        return nil
      end
      if state.layer and state.layer.Parent then
        return state.layer
      end
      state.gui = parent:FindFirstChild("ExodusPersistentNotifications")
        or context.inst("ScreenGui", {
          Name = "ExodusPersistentNotifications",
          DisplayOrder = context.theme.DISPLAY_ORDER,
          ResetOnSpawn = false,
          IgnoreGuiInset = true,
          ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        }, parent)
      if layerMount then
        scope.remove(layerMount)
      end
      layerMount = scope.add(context.deps.Runtime.mountLayer(state.gui, parent, context.theme.SCREEN_LAYERS.notifications))
      state.layer = state.gui:FindFirstChild("NotificationLayer")
        or context.inst("Frame", {
          Name = "NotificationLayer",
          Size = UDim2.fromScale(1, 1),
          BackgroundTransparency = 1,
          ZIndex = 100,
        }, state.gui)
      state.gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
      for _, card in ipairs(state.layer:GetChildren()) do
        if card.Name == "CornerNotifications" or card:GetAttribute("ExodusNotificationKey") and not card:FindFirstChild("Accent") then
          card:Destroy()
          continue
        end
        local id = card:GetAttribute("ExodusNotificationKey")
        if id and not table.find(state.order, id) then
          state.order[#state.order + 1] = id
        end
      end
      return state.layer
    end
    local function reflow(animated)
      if not state.layer then
        return
      end
      local offset = 24
      for index = #state.order, 1, -1 do
        if not state.layer:FindFirstChild("Notification_" .. state.order[index]) then
          table.remove(state.order, index)
        end
      end
      for _, id in ipairs(state.order) do
        local card = state.layer:FindFirstChild("Notification_" .. id)
        context.safeCancel(state.tweens[id])
        state.tweens[id] = context.twPlay(card, animated and "control" or 0, { Position = UDim2.new(0.5, 0, 1, -offset), GroupTransparency = 0 })
        offset += card.Size.Y.Offset + 8
      end
    end
    local function clear(id)
      id = key(id)
      if state.timers[id] then
        pcall(task.cancel, state.timers[id])
        state.timers[id] = nil
      end
      if not layer() then
        return
      end
      local card = state.layer:FindFirstChild("Notification_" .. id)
      local index = table.find(state.order, id)
      if index then
        table.remove(state.order, index)
      end
      if not card then
        reflow(true)
        return
      end
      context.safeCancel(state.tweens[id])
      local generation = (card:GetAttribute("ExodusNotificationGeneration") or 0) + 1
      card:SetAttribute("ExodusNotificationGeneration", generation)
      state.tweens[id] = context.twPlay(card, "control", {
        GroupTransparency = 1,
        Position = UDim2.new(0.5, 0, 1, card.Position.Y.Offset + 14),
      })
      local tween = state.tweens[id]
      local function finish()
        if not disposed and card.Parent and card:GetAttribute("ExodusNotificationGeneration") == generation then
          card:Destroy()
          state.tweens[id] = nil
          reflow(true)
        end
      end
      if tween then
        local connection
        connection = scope.connect(tween.Completed, function(status)
          scope.remove(connection)
          if status == Enum.PlaybackState.Completed then
            finish()
          end
        end)
      else
        finish()
      end
      return tween
    end
    local function show(message, id, kind, duration)
      local parent = layer()
      if not parent then
        return false
      end
      id = key(id)
      local card = parent:FindFirstChild("Notification_" .. id)
      if card and (not card:FindFirstChild("Content") or not card:FindFirstChild("Accent")) then
        card:Destroy()
        card = nil
      end
      if not card then
        card = Appearance.notification(parent, "Notification_" .. id)
      end
      card:SetAttribute("ExodusNotificationKey", id)
      card:SetAttribute("ExodusNotificationMessage", tostring(message))
      card:SetAttribute("ExodusNotificationKind", kind or "info")
      Appearance.updateNotification(card, message, kind, context.viewport())
      local generation = (card:GetAttribute("ExodusNotificationGeneration") or 0) + 1
      card:SetAttribute("ExodusNotificationGeneration", generation)
      if not table.find(state.order, id) then
        state.order[#state.order + 1] = id
      end
      reflow(true)
      if state.timers[id] then
        pcall(task.cancel, state.timers[id])
        state.timers[id] = nil
      end
      if duration and duration > 0 then
        state.timers[id] = task.delay(duration, function()
          state.timers[id] = nil
          if not disposed and card.Parent and card:GetAttribute("ExodusNotificationGeneration") == generation then
            clear(id)
          end
        end)
      end
      return true
    end
    local function persistent(message, id, kind, duration)
      id = key(id or message)
      local category = (id == "update" or id == "closing" or id == "loading") and "lifecycle" or (kind == "critical" and "critical" or "system")
      if not Policy.shouldShow(Utils.getConfig(), UIState.desktop, { category = category, topic = id }) then
        return false
      end
      if duration == nil and id ~= "dumper" then
        duration = 2.5
      end
      return show(message, id, kind, duration)
    end
    local function toast(message, important, event)
      event = important and { category = "critical" } or event or { category = "interaction" }
      if not Policy.shouldShow(Utils.getConfig(), UIState.desktop, event) then
        return false
      end
      local off = tostring(message):find(" Off", 1, true)
      return show(message, "toast", important and "critical" or (off and "warning" or "info"), 2.5)
    end
    layer()
    if state.layer then
      scope.connect(state.layer:GetPropertyChangedSignal("AbsoluteSize"), function()
        for _, id in ipairs(state.order) do
          local card = state.layer:FindFirstChild("Notification_" .. id)
          local message = card and card:GetAttribute("ExodusNotificationMessage")
          if message then
            Appearance.updateNotification(card, message, card:GetAttribute("ExodusNotificationKind"), context.viewport())
          end
        end
        reflow(false)
      end)
    end
    return { toast = toast, persistent = persistent, clear = clear, layer = layer, state = state, destroy = scope.destroy }
  end
  Controller.__contract = { provides = { "setup", "create" }, requires = {} }
  return Controller
end)()

return { __bundle = { uinotifications = __part_uinotifications, uinotificationview = __part_uinotificationview } }
