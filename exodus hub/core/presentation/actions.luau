-- [[ actions ]]
--!optimize 2
-- @modules uiactions

-- module
local Actions = {}
local Utils
local GameInfo
local Dumper

-- configuration
local CONFIG = {
  CONFIRM_SECONDS = 3,
}

-- setup
function Actions.setup(deps)
  Utils, GameInfo, Dumper = deps.Utils, deps.Hub, deps.Dumper
  return true
end

-- actions
function Actions.create(context)
  local scope, controls = context.scope, context.controls
  local GameInfo = context.hub or GameInfo
  local shortcuts = {}
  local handles, callbacks, states = {}, {}, {}
  local resetPending, resetGeneration = false, 0
  local function notify(message, important)
    if scope.alive then
      context.notify(message, important)
    end
  end
  local function persistent(message, kind, duration)
    if scope.alive then
      context.persistent(message, "dumper", kind, duration or 0)
    end
  end
  local function invoke(name, ...)
    if type(controls[name]) == "function" then
      return controls[name](...)
    end
  end
  callbacks.rejoin = function() invoke("onRejoin") end
  callbacks.serverHop = function() invoke("onServerHop") end
  callbacks.resetCharacter = function()
    local ok, reason = invoke("onResetCharacter")
    if ok == false then
      notify(reason or "Personagem indisponível", true)
    end
  end
  callbacks.resetSettings = function()
    local handle = handles.resetSettings
    if not resetPending then
      resetPending = true
      resetGeneration += 1
      local revision = resetGeneration
      handle.setText("Tap again to confirm")
      task.delay(CONFIG.CONFIRM_SECONDS, function()
        if scope.alive and revision == resetGeneration then
          resetPending = false
          handle.setText("Reset settings")
        end
      end)
      return
    end
    resetPending = false
    resetGeneration += 1
    local ok, result = pcall(Utils.resetConfig)
    if not ok or not result then
      notify("Reset failed", true)
      warn("[Exodus] Reset settings: " .. tostring(result))
      handle.setText("Reset settings")
      return
    end
    context.rebuild(true)
  end
  callbacks.dumper = function()
    persistent("Dumping...", "info")
    if Dumper.isRunning() then
      return
    end
    local accepted, reason = Dumper.start({
      onStatus = function(message) persistent(tostring(message), "info") end,
      onProgress = function(processed, total) persistent(("Dumping... %d/%d"):format(processed, total), "info") end,
      onComplete = function(result)
        persistent(
          ("Dump completed: %d saved, %d failed (%d recovered)."):format(result.saved, result.failed, result.recovered or 0),
          result.failed > 0 and "warning" or "success",
          5
        )
      end,
      onCanceled = function() persistent("Dumping canceled.", "warning", 1.5) end,
      onError = function(message)
        warn("[Exodus Dumper] " .. tostring(message))
        persistent("Dumper failed. Check the console.", "critical", 2.5)
      end,
    })
    if not accepted then
      warn("[Exodus Dumper] " .. tostring(reason))
      persistent("Dumper is already running.", "warning", 2)
    end
  end
  local gameActions = GameInfo.createActions(context)
  for name, callback in pairs(gameActions.callbacks or {}) do
    assert(not callbacks[name], "Duplicate game action: " .. name)
    callbacks[name] = callback
  end
  for name, read in pairs(gameActions.states or {}) do
    states[name] = read
  end
  local viewActions = context.actionFactory and context.actionFactory(context) or {}
  for name, callback in pairs(viewActions.callbacks or {}) do
    assert(not callbacks[name], "Duplicate UI action: " .. name)
    callbacks[name] = callback
  end
  for name, read in pairs(viewActions.states or {}) do
    states[name] = read
  end

  local result = {}
  function result.resolve(definition)
    definition.toast = false
    definition.expandedDescription = context.desktop and definition.desktopExpanded == true
    if not context.desktop then
      definition.shortcutKey = nil
    end
    if definition.action == "notifications" then
      definition.key = context.desktop and "DesktopNotifications" or "MobileNotifications"
    end
    if viewActions.resolve then
      viewActions.resolve(definition)
    end
    if definition.action then
      assert(
        definition.action == "notifications" or (callbacks[definition.action] or controls[definition.action]),
        "Unknown UI action: " .. tostring(definition.action)
      )
      definition.onClick = callbacks[definition.action] or controls[definition.action]
      definition.onChange = callbacks[definition.action] or controls[definition.action]
      definition.getState = states[definition.action] or definition.getState
    end
    return definition
  end
  function result.attach(definition, handle)
    if gameActions.attach then
      gameActions.attach(definition, handle)
    end
    if definition.action then
      handles[definition.action] = handle
    end
    if definition.shortcutKey then
      local entry = { definition = definition, handle = handle }
      if definition.shortcutPriority == 0 then
        table.insert(shortcuts, 1, entry)
      else
        shortcuts[#shortcuts + 1] = entry
      end
    end
  end
  function result.validateShortcut(key, binding)
    if binding == Enum.KeyCode.Unknown then
      return true
    end
    for _, entry in ipairs(shortcuts) do
      local definition = entry.definition
      if definition.shortcutKey ~= key and Utils.getConfigValue(definition.shortcutKey) == binding then
        return false, "Shortcut already used: " .. definition.title
      end
    end
    return true
  end
  function result.triggerShortcut(binding, priorityOnly)
    if binding == Enum.KeyCode.Unknown then
      return false
    end
    for _, entry in ipairs(shortcuts) do
      local definition, handle = entry.definition, entry.handle
      if (not priorityOnly or definition.shortcutPriority == 0) and Utils.getConfigValue(definition.shortcutKey) == binding then
        if definition.abilityOnly and context.abilitiesEnabled and not context.abilitiesEnabled() then
          return false
        end
        if not handle.activate or not handle.activate() then
          return false
        end
        if not definition.silentShortcut then
          local message = definition.title
          if definition.kind == "toggle" or definition.kind == "checkbox" then
            message = message .. (handle.getValue() and " On" or " Off")
          end
          context.notify(message, false, { category = "shortcut", topic = definition.action or definition.key })
        end
        return true
      end
    end
    return false
  end
  function result.refreshStates()
    for name, read in pairs(states) do
      local handle = handles[name]
      if handle and handle.setValue then
        handle.setValue(read())
      end
    end
  end
  scope.add(function()
    resetGeneration += 1
  end)
  return result
end

-- contract
Actions.__contract = {
  provides = { "setup", "create" },
  requires = { Utils = "utils", Hub = "hubapi", Dumper = "dumper" },
  requiresMethods = {
    Utils = { "getConfigValue", "isActive", "observeConfig", "resetConfig", "recordError" },
    Hub = { "createActions" },
    Dumper = { "start", "isRunning" },
  },
}

return Actions
