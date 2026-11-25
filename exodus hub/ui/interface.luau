-- [[ ui ]]
--!optimize 2
-- @modules ui

-- module
local ExodusUI = {}
local active
local configuredIcon, iconOverride

-- configuration

-- public-components
local Components = {}
for _, name in ipairs({
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
  local context = deps.Context.create(deps, preview and preview.deviceDesktop)
  active = context
  context.hub = deps.GameContext.getProfile()
  local hubUI = deps.Hub.getUIConfig()
  context.combatUI = hubUI.combatUI == true
  context.abilityKeys = hubUI.abilityKeys or {}
  context.miniControls = hubUI.miniControls
  context.notifications = deps.Notifications.create(context)
  context.notifications.layer()
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
    local manual = deps.Utils.isManualSpamActive()
    if context.state.spamOn ~= manual then
      context.floating.setSpam(manual)
    end
    context.actions.refreshManual()
  end))
  context.scope.add(deps.Utils.observeConfig(function(changes)
    context.floating.sync(changes)
    context.actions.refreshManual()
    if changes.ForcePCUI ~= nil then
      rebuild()
    end
  end))
  if preview and preview.open then
    context.window.toggle()
  end
  return true
end

function ExodusUI.notify(...)
  if active and active.scope.alive then
    active.notifications.persistent(...)
  end
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
    Telemetry = { "create" },
    Input = { "create" },
    Assists = { "create" },
    Lifecycle = { "create" },
    Information = { "snapshot" },
    Details = { "create" },
  },
  requiresData = { UIConfig = { "pages" }, Theme = { "tokens" } },
  data = { "Components" },
  provides = { "setup", "notify", "setIcon" },
}

return ExodusUI
