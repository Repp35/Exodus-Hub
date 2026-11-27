--!optimize 2
-- @modules diagnostics

local Diagnostics = {}
function Diagnostics.setup() return true end
function Diagnostics.create(deps)
  local collector = {}
  local state, CONFIG = deps.state, deps.config
  local snapshot, lifecycleSnapshot = deps.snapshot, deps.lifecycleSnapshot
  local refreshPending = false
  local function append(list, value)
    list[#list + 1] = value
    if #list > CONFIG.HISTORY_LIMIT then
      table.remove(list, 1)
    end
  end
  local function refreshNamespace() deps.refresh() end
  local function diagnosticsSnapshot(includeModules)
    local statuses = {}
    local source = deps.getModules().status
    if includeModules ~= false and type(source) == "table" and type(source.collect) == "function" then
      local ok, result = pcall(source.collect)
      if ok and type(result) == "table" then
        statuses = snapshot(result)
      end
    end
    local diagnostics = state.diagnostics
    return {
      schema = CONFIG.API_VERSION,
      generatedAt = os.clock(),
      lastError = snapshot(diagnostics.lastError),
      lastTransition = snapshot(diagnostics.lastTransition),
      lastTransitionAt = diagnostics.lastTransitionAt,
      errors = snapshot(diagnostics.errors),
      transitions = snapshot(diagnostics.transitions),
      lifecycle = lifecycleSnapshot(),
      runtime = {
        active = state.active,
      },
      modules = statuses,
    }
  end
  local function recordTransition(source, fromState, toState, reason)
    local item = {
      source = tostring(source or "Unknown"),
      from = tostring(fromState or ""),
      to = tostring(toState or ""),
      reason = tostring(reason or ""),
      at = os.clock(),
    }

    state.diagnostics.lastTransition, state.diagnostics.lastTransitionAt = item, item.at
    append(state.diagnostics.transitions, item)
    if state.active and not refreshPending then
      refreshPending = true
      local generation = state.lifecycle.generation
      task.delay(0.1, function()
        refreshPending = false
        if state.active and state.lifecycle.generation == generation then
          refreshNamespace()
        end
      end)
    end
  end
  function collector.recordError(source, message)
    source, message = tostring(source or "Unknown"), tostring(message or "")
    local previous = state.diagnostics.lastError
    if previous and previous.source == source and previous.message == message and os.clock() - previous.at < 1 then
      previous.count = (previous.count or 1) + 1
      return true
    end
    local item = { source = tostring(source or "Unknown"), message = tostring(message or ""), at = os.clock() }
    state.diagnostics.lastError = item
    append(state.diagnostics.errors, item)
    warn(("[%s] %s"):format(item.source, item.message))
    refreshNamespace()
    return true
  end
  collector.snapshot = diagnosticsSnapshot
  collector.recordTransition = recordTransition
  return collector
end
Diagnostics.__contract = { requires = {}, provides = { "setup", "create" } }
return Diagnostics
