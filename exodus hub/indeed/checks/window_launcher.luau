-- [[ window launcher regression; Roblox drawing is not emulated ]]

-- code
local function uiSignal()
  local callbacks = {}; local event = {}
  function event:Connect(callback)
    callbacks[#callbacks + 1] = callback
    return { Disconnect = function() end }
  end
  function event:Fire()
    for _, callback in ipairs(callbacks) do
      callback()
    end
  end
  return event
end
local function instance(_, properties, parent)
  local object = { Parent = parent, Visible = true }
  for _, event in ipairs({ "Activated", "MouseEnter", "MouseLeave" }) do
    object[event] = uiSignal()
  end
  for key, value in pairs(properties or {}) do
    object[key] = value
  end
  return object
end
local deferred = {}
task.defer = function(callback) deferred[#deferred + 1] = callback end
for _, combatUI in ipairs({ false, true }) do
  for _, desktop in ipairs({ false, true }) do
    local drags = false
    local context = {
      combatUI = combatUI,
      deps = {
        Utils = {
          getConfig = function() return {} end,
          name = function() return "Exodus" end,
          version = function() return "test" end,
          author = function() return "test" end,
        },
      },
      theme = loaded.uitheme.tokens,
      state = { desktop = desktop, panelOpen = false, closing = false },
      refs = { screenGui = {} },
      scope = { alive = true },
      kit = { icon = function() end, dismiss = function() end },
      pages = { suspend = function() end },
      inst = instance,
      corner = function() end,
      stroke = function() return {} end,
      safeCancel = function() end,
      safeDisconnect = function() end,
      untrackConn = function() end,
      trackConn = function(connection) return connection end,
      twPlay = function(object, _, properties)
        for key, value in pairs(properties) do
          object[key] = value
        end
      end,
      makeDraggable = function()
        return function() return drags end
      end,
      makeBtn = function() return instance() end,
      setConfigValue = function() end,
      updateResponsiveScale = function() end,
    }

    local window = loaded.uiwindow.create(context)
    for _, callback in ipairs(deferred) do
      callback()
    end
    table.clear(deferred); local launcher, panel = context.refs.floatingButton, context.refs.configPanel
    assert(launcher and launcher.Parent == context.refs.screenGui, "Missing launcher")
    assert(launcher.Text == "E" and launcher.TextTransparency == 0 and launcher.BackgroundTransparency < 1, "Invisible launcher"); assert(not panel.Visible and not context.state.panelOpen)
    launcher.Activated:Fire(); assert(panel.Visible and panel.GroupTransparency == 0 and context.state.panelOpen, "Launcher did not open menu")
    drags = true; launcher.Activated:Fire()
    assert(panel.Visible and context.state.panelOpen, "Dragging toggled menu"); drags = false
    launcher.Activated:Fire(); assert(not panel.Visible and not context.state.panelOpen, "Launcher did not minimize menu")
    window.toggle(); assert(panel.Visible and context.state.panelOpen, "Menu cannot reopen")
    if not combatUI then
      loaded.uifloating.create(context); assert(context.refs.floatingButton == launcher, "Universal controller replaced launcher")
      assert(context.refs.clashBall == nil and context.refs.parryBall == nil and context.refs.miniGui == nil, "Combat widgets leaked")
    end
  end
end
print("Launcher opens, minimizes and reopens on mobile/PC in both game contexts")
