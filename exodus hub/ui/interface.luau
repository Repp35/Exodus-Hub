-- [[ interface ]]
--!optimize 2
-- @modules ui

-- module
local ExodusUI = {}
local active
local configuredDependencies
local pendingPages, pendingValues = {}, {}
local configuredIcon, iconOverride

-- configuration

-- public-components
local Components = {}
ExodusUI.Components = Components

-- composition
local function mount(options, preview)
  local deps = table.clone(assert(configuredDependencies, "UI library is not initialized"))
  deps.State, deps.Model, deps.Controls = options.state, options.model, options.controls
  deps.BeforePresent, deps.Information = options.beforePresent, options.information
  deps.MiniScale = options.miniScale
  if active then
    active.destroy()
    active = nil
  end
  local context = deps.Context.create(deps, preview and preview.deviceDesktop)
  context.options, context.handle = options, options.handle
  for name in pairs(context.kit.Components) do
    Components[name] = function(parent, options)
      assert(active and active.scope.alive, "UI is not initialized")
      return active.kit.Components[name](parent, options)
    end
  end
  context.brand = { name = options.name or "Exodus", author = options.author or "" }
  active = context
  local hubUI = options.definition
  context.hasConditions = options.conditionsEnabled ~= false
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
      local ok, reason = mount(options, { snapshot = not reset and snapshot or nil, open = wasOpen, deviceDesktop = context.state.deviceDesktop })
      if not ok then
        warn("[Exodus] Falha ao atualizar interface: " .. tostring(reason))
      end
    end)
  end
  context.rebuild = rebuild
  context.actions = (options.actionsFactory or deps.Commands.create)({
    scope = context.kit.scope,
    utils = deps.State,
    actionFactory = hubUI.createActions,
    actions = options.actions,
    controls = deps.Controls,
    desktop = context.state.desktop,
    notify = context.notifications.toast,
    persistent = context.notifications.persistent,
    setPrimaryActive = context.floating.setPrimaryActive,
    showPrimary = context.floating.showPrimary,
    rebuild = rebuild,
    abilitiesEnabled = deps.Model.conditionsEnabled,
  })
  context.pages = deps.UIPages.create(context.kit, context.refs.configPanel, hubUI.pages, {
    desktop = context.state.desktop,
    capabilities = options.capabilities or {},
    read = deps.State.getConfigValue,
    resolve = context.actions.resolve,
    onComponent = context.actions.attach,
    onError = function(name, reason, title)
      deps.State.recordError("UI." .. tostring(name), reason)
      context.notifications.toast("Falha ao carregar " .. tostring(title) .. ".", true)
    end,
    abilitiesEnabled = deps.Model.conditionsEnabled,
    onNavigate = context.window.updateNavigation,
  })
  if options.information then
    deps.Details.create(context)
  end
  context.floating.refreshAbilities()
  context.updateResponsiveScale()
  deps.Input.create(context)
  deps.Assists.create(context)
  if preview and preview.snapshot then
    context.pages.restore(preview.snapshot)
  end
  context.scope.add(deps.Model.observeState(function()
    local primary = context.inputDefinition.primary
    local manual = primary and deps.Controls[primary.read] and deps.Controls[primary.read]() or false
    if context.state.primaryActive ~= manual then
      context.floating.setPrimaryActive(manual)
    end
    context.actions.refreshStates()
  end))
  context.scope.add(deps.State.observeConfig(function(changes)
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

function ExodusUI.setup(deps)
  for alias in pairs(ExodusUI.__contract.requires) do
    assert(type(deps[alias]) == "table", "Missing UI dependency: " .. alias)
  end
  configuredDependencies = deps
  return true
end
local function pageBuilder(definition, changed, state)
  local page = {}
  function page.addSection(section)
    section = table.clone(section or {})
    section.components = table.clone(section.components or {})
    definition.sections = definition.sections or {}
    definition.sections[#definition.sections + 1] = section
    changed()
    local target = {}
    function target.add(kind, component)
      component = table.clone(component or {})
      component.kind = kind
      section.components[#section.components + 1] = component
      changed()
      return {
        getValue = function() return state.read(component.key, component.value) end,
        setValue = function(value) return state.write(assert(component.key, "Control has no key"), value) end,
        setText = function(value)
          component.title = tostring(value)
          changed()
        end,
      }
    end
    return setmetatable(target, {
      __index = function(_, kind)
        return function(component) return target.add(kind, component) end
      end,
    })
  end
  return page
end
function ExodusUI.create(options)
  options = options or {}
  local values, observers = { MobileNotifications = true, DesktopNotifications = true, DesktopShortcutNotifications = true }, {}
  for key, value in pairs(options.defaults or {}) do
    values[key] = value
  end
  local state = table.clone(options.state or {})
  state.getConfigValue = state.getConfigValue or options.read or function(key) return values[key] end
  state.getConfig = state.getConfig
    or options.snapshot
    or function()
      local result = table.clone(values)
      if options.read then
        for _, key in ipairs({ "MobileNotifications", "DesktopNotifications", "DesktopShortcutNotifications", "BtnX", "BtnY", "PanelX", "PanelY", "ForcePCUI" }) do
          local value = options.read(key)
          if value ~= nil then
            result[key] = value
          end
        end
      end
      return result
    end
  state.setConfig = state.setConfig
    or function(patch)
      if options.write and options.write(patch) == false then
        return false
      end
      for key, value in pairs(patch) do
        values[key] = value
      end
      for _, callback in pairs(observers) do
        callback(table.freeze(table.clone(patch)))
      end
      return true
    end
  state.observeConfig = state.observeConfig
    or options.observe
    or function(callback)
      local connection = {}
      observers[connection] = callback
      function connection:Disconnect() observers[self] = nil end
      return connection
    end
  state.recordError = state.recordError or function(source, message) warn(tostring(source) .. ": " .. tostring(message)) end
  state.isActive = state.isActive or function() return active and active.scope.alive or false end
  options.state = state
  local function emptyObserver()
    return { Disconnect = function() end }
  end
  local model = table.clone(options.model or {})
  model.getAvailability = model.getAvailability or function() return true end
  model.getChoices = model.getChoices or function() return {} end
  model.getReadouts = model.getReadouts or function() return {} end
  model.getVisibility = model.getVisibility or function() return {} end
  model.conditionsEnabled = model.conditionsEnabled or function() return true end
  model.observeState = model.observeState or emptyObserver
  options.model, options.controls = model, options.controls or {}
  options.definition = options.definition or { pages = options.pages or {}, miniBalls = options.mini or {} }
  for _, page in ipairs(pendingPages) do
    options.definition.pages[#options.definition.pages + 1] = page
  end
  pendingPages = {}
  if next(pendingValues) then
    state.setConfig(pendingValues)
    pendingValues = {}
  end
  if #options.definition.pages == 0 then
    options.definition.pages = { { id = "__empty", title = "", columns = 1, sections = {} } }
  end
  local ok, reason = mount(options)
  assert(ok, reason)
  local owner = active
  local function live()
    assert(active and active.options == options and active.scope.alive, "Window is destroyed")
    return active
  end
  local handle = {
    Components = setmetatable({}, { __index = function(_, key) return live().kit.Components[key] end }),
    notify = function(...) return live().notifications.persistent(...) end,
    notifyCorner = function(...) return live().cornerNotifications.show(...) end,
    createMini = function(...) return live().floating.add(...) end,
    destroy = function()
      if active and active.options == options then
        active.destroy()
        active = nil
      end
    end,
    toggle = function() return live().window.toggle() end,
    fade = function() return live().lifecycle.fade() end,
    snapshot = function() return live().pages.snapshot() end,
    restore = function(value) return live().pages.restore(value) end,
    setReadout = function(...) return live().pages.setReadout(...) end,
    getControl = function(...) return live().pages.getControl(...) end,
  }
  options.handle = handle
  function handle.addPage(definition)
    assert(type(definition) == "table" and type(definition.id) == "string", "Page definition required")
    local pages = options.definition.pages
    if pages[1] and pages[1].id == "__empty" then
      table.remove(pages, 1)
    end
    for _, page in ipairs(pages) do
      assert(page.id ~= definition.id, "Duplicate page: " .. definition.id)
    end
    pages[#pages + 1] = definition
    if active and active.scope.alive then
      active.rebuild()
    end
    return pageBuilder(definition, function()
      if active and active.options == options and active.scope.alive then
        active.rebuild()
      end
    end, { read = state.getConfigValue, write = function(key, value) return state.setConfig({ [key] = value }) end })
  end
  owner.handle = handle
  if options.icon then
    ExodusUI.setIcon(options.icon)
  end
  return handle
end
function ExodusUI.teardown()
  if active then
    active.destroy()
    active = nil
  end
  pendingPages, pendingValues = {}, {}
  return true
end
function ExodusUI.addPage(definition)
  if active and active.scope.alive and active.handle then
    return active.handle.addPage(definition)
  end
  definition = table.clone(definition)
  definition.title, definition.columns = definition.title or definition.id, definition.columns or 1
  definition.sections = table.clone(definition.sections or {})
  for _, page in ipairs(pendingPages) do
    assert(page.id ~= definition.id, "Duplicate page: " .. tostring(definition.id))
  end
  pendingPages[#pendingPages + 1] = definition
  return pageBuilder(definition, function()
    if active and active.scope.alive then
      active.rebuild()
    end
  end, {
    read = function(key, fallback)
      if active then
        return active.options.state.getConfigValue(key)
      end
      local value = pendingValues[key]
      if value == nil then
        return fallback
      end
      return value
    end,
    write = function(key, value)
      if active then
        return active.options.state.setConfig({ [key] = value })
      end
      pendingValues[key] = value
      return true
    end,
  })
end
function ExodusUI.createWorldLabel(...) return assert(configuredDependencies, "Initialize the UI library").Markers.label(...) end
function ExodusUI.createWorldBillboard(...) return assert(configuredDependencies, "Initialize the UI library").Markers.billboard(...) end
function ExodusUI.createWorldHighlight(...) return assert(configuredDependencies, "Initialize the UI library").Markers.highlight(...) end
function ExodusUI.destroyWorldMarker(...) return assert(configuredDependencies, "Initialize the UI library").Markers.destroy(...) end
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
  access = { default = "ui.use", methods = { setup = "lifecycle.write", create = "ui.use", createMini = "ui.use", addPage = "ui.use" } },
  requires = {
    Markers = "uiworldmarkers",
    UIKit = "uikit",
    UIPages = "uipages",
    Commands = "uicommands",
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
    Details = "uidetails",
    NotificationPolicy = "uinotifications",
  },
  requiresMethods = {
    Markers = { "label", "billboard", "highlight", "destroy" },
    UIKit = { "create" },
    UIPages = { "create" },
    Commands = { "create" },
    Runtime = { "scope", "motion", "isVisible", "mountLayer" },
    Appearance = { "notification", "updateNotification" },
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
    Details = { "create" },
    NotificationPolicy = { "shouldShow" },
  },
  requiresData = { Theme = { "tokens" } },
  data = { "Components" },
  provides = {
    "setup",
    "teardown",
    "create",
    "createMini",
    "addPage",
    "notify",
    "notifyCorner",
    "setIcon",
    "createWorldLabel",
    "createWorldBillboard",
    "createWorldHighlight",
    "destroyWorldMarker",
  },
}
return ExodusUI
