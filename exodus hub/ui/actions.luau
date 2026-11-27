-- [[ generic component actions and shortcuts ]]
--!optimize 2
-- @modules uicommands
local Commands = {}
function Commands.setup() return true end
function Commands.create(context)
  local shortcuts, handles, result = {}, {}, {}
  local actions = context.actions or {}
  function result.resolve(definition)
    if definition.action then
      local callback = assert((actions.callbacks or {})[definition.action], "Unknown action: " .. tostring(definition.action))
      definition.onClick, definition.onChange = callback, callback
      definition.getState = (actions.states or {})[definition.action]
    end
    if actions.resolve then
      actions.resolve(definition)
    end
    return definition
  end
  function result.attach(definition, handle)
    if definition.shortcutKey then
      shortcuts[#shortcuts + 1] = { definition = definition, handle = handle }
    end
    if definition.action then
      handles[definition.action] = handle
    end
    if actions.attach then
      actions.attach(definition, handle)
    end
  end
  function result.validateShortcut(key, binding)
    if binding == Enum.KeyCode.Unknown then
      return true
    end
    for _, entry in ipairs(shortcuts) do
      if entry.definition.shortcutKey ~= key and context.utils.getConfigValue(entry.definition.shortcutKey) == binding then
        return false, "Atalho já usado"
      end
    end
    return true
  end
  function result.triggerShortcut(binding, priorityOnly)
    for _, entry in ipairs(shortcuts) do
      if
        (not priorityOnly or entry.definition.shortcutPriority == 0)
        and context.utils.getConfigValue(entry.definition.shortcutKey) == binding
        and entry.handle.activate
      then
        return entry.handle.activate()
      end
    end
    return false
  end
  function result.refreshStates()
    for name, read in pairs(actions.states or {}) do
      local handle = handles[name]
      if handle and handle.setValue then
        handle.setValue(read())
      end
    end
  end
  return result
end
Commands.__contract = { provides = { "setup", "create" }, requires = {} }
return Commands
