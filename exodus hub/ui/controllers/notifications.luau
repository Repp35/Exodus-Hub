-- [[ notifications ]]
--!optimize 2
-- @modules uinotifications, uinotificationview

-- code
local __part_uinotifications = (function()
  local Notifications = {}
  local CONFIG = { SILENT_TOPICS = {} }
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
    local Utils, UIState = context.deps.State, context.state
    local Appearance, Policy = context.deps.Appearance, context.deps.NotificationPolicy
    local surface = context.deps.Surface.create(Appearance)
    local function key(value) return tostring(value or "general"):gsub("[^%w_%-]", "_") end
    local layer, show, clear = surface.layer, surface.show, surface.clear
    local function persistent(message, id, kind, duration)
      id = key(id or message)
      local category = kind == "critical" and "critical" or "system"
      if not Policy.shouldShow(Utils.getConfig(), UIState.desktop, { category = category, topic = id }) then
        return false
      end
      if duration == nil then
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
    local root = layer()
    if root then
      context.scope.add(context.deps.Runtime.mountLayer(root.Parent, root.Parent.Parent, context.theme.SCREEN_LAYERS.notifications))
    end
    return { toast = toast, persistent = persistent, clear = clear, layer = layer }

  end
  Controller.__contract = { provides = { "setup", "create" }, requires = {} }
  return Controller
end)()

return { __bundle = { uinotifications = __part_uinotifications, uinotificationview = __part_uinotificationview } }
