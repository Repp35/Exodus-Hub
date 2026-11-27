-- [[ interface ]]
--!optimize 2
-- @modules ui

-- module
local ExodusUI = {}
local active
local configuredDependencies
local configuredIcon, iconOverride

-- configuration

-- public-components
local Components = {}
for _, name in ipairs({
  "mini",
  "spam",
  "label",
  "button",
  "textInput",
  "number",
  "toggle",
  "divider",
  "progressBar",
  "dropdown",
  "slider",
  "segmented",
  "tabs",
  "rate_selector",
}) do
  Components[name] = function(parent, options)
    assert(active and active.kit and active.scope.alive, "Call ExodusUI.setup before creating components, or use UIKit.create for a standalone library")
    return active.kit.Components[name](parent, options)
  end
end
ExodusUI.Components = Components

-- composition
function ExodusUI.setup(deps, preview)
  if type(deps) ~= "table" or type(deps.Controls) ~= "table" then
    return false, "missing UI dependencies"
  end
  for alias in pairs(ExodusUI.__contract.requires) do
    if type(deps[alias]) ~= "table" then
      return false, "missing UI dependency: " .. alias
    end
  end
  for alias, methods in pairs(ExodusUI.__contract.requiresMethods) do
    for _, method in ipairs(methods) do
      if type(deps[alias][method]) ~= "function" then
        return false, "missing UI method: " .. alias .. "." .. method
      end
    end
  end
  if type(_G.ExodusUICleanup) == "function" then
    if not preview and type(_G.ExodusUIFadeOut) == "function" then
      pcall(_G.ExodusUIFadeOut)
    end
    _G.ExodusUICleanup()
  else
    local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("ExodusUISystem")
    if old then
      old:Destroy()
    end
  end
  configuredDependencies = deps
  local context = deps.Context.create(deps, preview and preview.deviceDesktop)
  context.brand = deps.Brand or { name = deps.Utils.name(), author = deps.Utils.author() }
  active = context
  context.hub = deps.GameContext.getProfile()
  local hubUI = deps.Hub.getUIConfig()
  context.combatUI = hubUI.combatUI == true
  context.inputDefinition = hubUI.input or {}
  context.abilityKeys = hubUI.abilityKeys or {}
  context.miniBalls = hubUI.miniBalls or {}
  context.notifications = deps.Notifications.create(context)
  context.notifications.layer()
  context.cornerNotifications = deps.CornerNotifications.create(context)
  context.floating = deps.Floating.create(context)
  context.window = deps.Window.create(context)
  if iconOverride then
    context.window.setIcon(configuredIcon)
  else
    context.window.setIcon(deps.Theme.tokens.ICON)
  end
  deps.Telemetry.create(context)
  context.lifecycle = deps.Lifecycle.create(context)
  local function cleanup()
    context.destroy()
    if _G.ExodusUICleanup == cleanup then
      if active == context then
        active = nil
      end
      _G.ExodusUICleanup, _G.ExodusUIFadeOut, _G.ExodusUIRestore = nil, nil, nil
      _G.ExodusShowPersistentNotification, _G.ExodusClearPersistentNotification = nil, nil
    end
  end
  _G.ExodusUICleanup = cleanup
  _G.ExodusUIFadeOut = context.lifecycle.fade
  _G.ExodusUIRestore = context.lifecycle.restore
  _G.ExodusShowPersistentNotification = context.notifications.persistent
  _G.ExodusClearPersistentNotification = context.notifications.clear
  local rebuildQueued = false
  local function rebuild(reset)
    if rebuildQueued then
      return
    end
    rebuildQueued = true
    local owner = context.refs.screenGui
    local wasOpen, snapshot = context.state.panelOpen, context.pages.snapshot()
    task.defer(function()
      if not context.scope.alive or not owner.Parent or context.state.closing then
        return
      end
      local ok, reason = ExodusUI.setup(deps, { snapshot = not reset and snapshot or nil, open = wasOpen, deviceDesktop = context.state.deviceDesktop })
      if not ok then
        warn("[Exodus] Falha ao atualizar interface: " .. tostring(reason))
      end
    end)
  end
  context.actions = deps.UIActions.create({
    scope = context.kit.scope,
    hub = deps.Hub,
    utils = deps.Utils,
    actionFactory = hubUI.createActions,
    controls = deps.Controls,
    desktop = context.state.desktop,
    notify = context.notifications.toast,
    persistent = context.notifications.persistent,
    setSpam = context.floating.setSpam,
    showMini = context.floating.showMini,
    rebuild = rebuild,
    abilitiesEnabled = deps.Hub.areAbilitiesEnabled,
  })
  context.pages = deps.UIPages.create(context.kit, context.refs.configPanel, deps.UIPages.forGame(deps.UIConfig.getPages(hubUI), context.combatUI), {
    desktop = context.state.desktop,
    capabilities = { clashPrediction = context.combatUI and deps.Hub.hasClashPrediction() },
    read = deps.Utils.getConfigValue,
    resolve = context.actions.resolve,
    onComponent = context.actions.attach,
    onError = function(name, reason, title)
      deps.Utils.recordError("UI." .. tostring(name), reason)
      context.notifications.toast("Falha ao carregar " .. tostring(title) .. ".", true)
    end,
    abilitiesEnabled = deps.Hub.areAbilitiesEnabled,
    onNavigate = context.window.updateNavigation,
  })
  deps.Details.create(context)
  context.floating.refreshAbilities()
  context.updateResponsiveScale()
  deps.Input.create(context)
  deps.Assists.create(context)
  if preview and preview.snapshot then
    context.pages.restore(preview.snapshot)
  end
  context.scope.add(deps.Utils.observeSpam(function()
    local primary = context.inputDefinition.primary
    local manual = primary and deps.Controls[primary.read] and deps.Controls[primary.read]() or false
    if context.state.spamOn ~= manual then
      context.floating.setSpam(manual)
    end
    context.actions.refreshStates()
  end))
  context.scope.add(deps.Utils.observeConfig(function(changes)
    context.floating.sync(changes)
    context.actions.refreshStates()
    if changes.ForcePCUI ~= nil then
      rebuild()
    end
  end))
  if not context.window.present(not preview and deps.BeforePresent or nil) then
    return false, "UI initialization canceled"
  end
  context.floating.sync()
  if preview and preview.open then
    context.window.toggle()
  end
  return true
end

function ExodusUI.notify(...)
  if active and active.scope.alive then
    return active.notifications.persistent(...)
  end
  return false
end

function ExodusUI.notifyCorner(title, message, options)
  if active and active.scope.alive then
    return active.cornerNotifications.show(title, message, options)
  end
  return false
end

function ExodusUI.createMini(definition)
  assert(active and active.scope.alive, "UI is not initialized")
  return active.floating.add(definition)
end

function ExodusUI.create(options, dependencies)
  options = options or {}
  local deps = table.clone(dependencies or assert(configuredDependencies, "Initialize the UI modules before creating a menu"))
  local values, observers = { MobileNotifications = true, DesktopNotifications = true, DesktopShortcutNotifications = true, ForcePCUI = false }, {}
  for key, value in pairs(options.defaults or {}) do
    values[key] = value
  end
  local utils = table.clone(deps.Utils)
  utils.name = function() return options.name or "Exodus Hub" end
  utils.author = function() return options.author or "" end
  utils.getConfig = function() return table.clone(values) end
  utils.getConfigValue = options.read or function(key) return values[key] end
  utils.setConfig = function(patch)
    if options.write and options.write(patch) == false then
      return false
    end
    for key, value in pairs(patch) do
      values[key] = value
    end
    for _, callback in pairs(observers) do
      callback(patch)
    end
    return true
  end
  utils.observeConfig = options.observe
    or function(callback)
      local connection = {}
      observers[connection] = callback
      function connection:Disconnect() observers[self] = nil end
      return connection
    end
  utils.isManualSpamActive = function() return false end
  utils.setManualSpamActive = function() end
  utils.observeSpam = function()
    return { Disconnect = function() end }
  end
  utils.resetConfig = function() return utils.setConfig(table.clone(options.defaults or {})) end
  utils.stop = function()
    if active then
      active.destroy()
    end
  end
  local definition = options.definition or { pages = options.pages or {}, miniBalls = options.mini or {} }
  local hub = table.clone(deps.Hub)
  hub.getUIConfig = function() return definition end
  hub.getReadouts = function() return options.readouts or {} end
  hub.getChoices = function() return {} end
  hub.createActions = function() return {} end
  hub.getMiniVisibility = function() return {} end
  hub.hasClashPrediction = function() return false end
  hub.areAbilitiesEnabled = function() return false end
  hub.getAbilityAvailability = function() return false end
  hub.observeAbilityMode = function()
    return { Disconnect = function() end }
  end
  deps.Utils, deps.Hub = utils, hub
  deps.UIConfig = { pages = definition.pages, getPages = function() return definition.pages end }
  deps.GameContext = { getProfile = function() return { id = "external", title = utils.name(), version = options.version } end }
  deps.Controls = table.clone(options.controls or {})
  deps.Controls.onClose = deps.Controls.onClose or utils.stop
  deps.Brand = { name = utils.name(), author = utils.author() }
  deps.BeforePresent = nil
  local ok, reason = ExodusUI.setup(deps)
  assert(ok, reason)
  local owner = active
  if options.icon then
    ExodusUI.setIcon(options.icon)
  end
  return {
    Components = owner.kit.Components,
    notify = owner.notifications.persistent,
    notifyCorner = owner.cornerNotifications.show,
    createMini = owner.floating.add,
    destroy = owner.destroy,
    toggle = owner.window.toggle,
  }
end

function ExodusUI.setIcon(image)
  assert(image == nil or type(image) == "string" or type(image) == "number", "Icon must be an asset id or image URI")
  if type(image) == "number" or (type(image) == "string" and image:match("^%d+$")) then
    image = "rbxassetid://" .. tostring(image)
  end
  if image == "" then
    image = nil
  end
  configuredIcon, iconOverride = image, true
  if active and active.scope.alive then
    active.window.setIcon(image)
  end
  return true
end

-- contract
ExodusUI.__contract = {
  requires = {
    Utils = "utils",
    GameContext = "gamecontext",
    UIConfig = "uiconfig",
    Hub = "hubapi",
    UIKit = "uikit",
    UIPages = "uipages",
    UIActions = "uiactions",
    NotificationPolicy = "uinotifications",
    Runtime = "uiruntime",
    Theme = "uitheme",
    Appearance = "uiappearance",
    Context = "uicontext",
    Window = "uiwindow",
    Header = "uiheader",
    Floating = "uifloating",
    Notifications = "uinotificationview",
    Surface = "uisurface",
    CornerNotifications = "uicornernotification",
    Telemetry = "uitelemetry",
    Input = "uiinput",
    Assists = "uiassists",
    Lifecycle = "uilifecycle",
    Information = "information",
    Details = "uidetails",
  },
  requiresMethods = {
    GameContext = { "getProfile" },
    Utils = {
      "getConfig",
      "getConfigValue",
      "getLocalPlayer",
      "isActive",
      "isManualSpamActive",
      "setConfig",
      "resetConfig",
      "setManualSpamActive",
      "normalizeSpamRate",
      "observeConfig",
      "observeSpam",
      "recordError",
      "stop",
      "name",
      "version",
      "author",
    },
    Hub = {
      "getUIConfig",
      "getChoices",
      "getReadouts",
      "hasClashPrediction",
      "getAbilityAvailability",
      "getGameContext",
      "areAbilitiesEnabled",
      "observeAbilityMode",
    },
    Appearance = { "notification", "updateNotification" },
    UIConfig = { "getPages" },
    UIKit = { "create" },
    UIPages = { "create", "forGame" },
    UIActions = { "create" },
    NotificationPolicy = { "shouldShow" },
    Runtime = { "scope", "motion", "isVisible", "mountLayer" },
    Context = { "create" },
    Window = { "create" },
    Header = { "create" },
    Floating = { "create" },
    Notifications = { "create" },
    Surface = { "create" },
    CornerNotifications = { "create" },
    Telemetry = { "create" },
    Input = { "create" },
    Assists = { "create" },
    Lifecycle = { "create" },
    Information = { "snapshot" },
    Details = { "create" },
  },
  requiresData = { UIConfig = { "pages" }, Theme = { "tokens" } },
  data = { "Components" },
  provides = { "setup", "create", "createMini", "notify", "notifyCorner", "setIcon" },
}

return ExodusUI
