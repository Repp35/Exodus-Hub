-- [[ diagnostics ]]
-- @modules profiler, status, diagnostics

-- code
local __part_status = (function()
  local Status = {}
  local active
  function Status.setup() return true end
  function Status.create(providers, reportError)
    local names, failures, reading = {}, {}, {}
    for name, provider in pairs(providers) do
      if type(provider) == "table" and type(provider.getStatus) == "function" then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    local reader = {}
    function reader.get(name)
      local provider = providers[name]
      if reading[name] or type(provider) ~= "table" or type(provider.getStatus) ~= "function" then
        return nil
      end
      reading[name] = true
      local ok, value = pcall(provider.getStatus)
      reading[name] = nil
      if ok and type(value) == "table" then
        failures[name] = nil
        return value
      end
      if not failures[name] then
        failures[name] = true
        if type(reportError) == "function" then
          pcall(reportError, "Status", name .. ": " .. tostring(ok and "invalid status" or value))
        end
      end
      return nil
    end
    function reader.collect(selected)
      local result = {}
      for _, name in ipairs(selected or names) do
        local value = reader.get(name)
        if value then
          result[name] = value
        end
      end
      return result
    end
    return reader
  end
  function Status.configure(providers, reportError)
    if type(providers) ~= "table" then
      return false, "provedores de status inválidos"
    end
    active = Status.create(providers, reportError)
    return true
  end
  function Status.get(name) return active and active.get(name) or nil end
  function Status.collect(selected) return active and active.collect(selected) or {} end
  Status.__contract = {
    access = {
      default = "internal.read",
      methods = { configure = "infrastructure.write" },
    },
    provides = { "setup", "create", "configure", "get", "collect" },
    requires = {},
  }
  return Status
end)()
local __part_diagnostics = (function()
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
          manualSpamActive = state.manualSpam,
          autoSpamActive = state.autoSpam,
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
end)()
local __part_profiler = (function()
  local Profiler = {}
  local enabled = false
  local samples = {}
  local CONFIG = {
    LIMIT = 64,
  }

  local LIMIT = CONFIG.LIMIT
  function Profiler.setup() return true end
  function Profiler.setEnabled(value)
    enabled = value == true
    table.clear(samples)
  end
  function Profiler.isEnabled() return enabled end
  function Profiler.begin(name)
    if not enabled then
      return nil
    end
    if debug.profilebegin then
      debug.profilebegin(name)
    end
    return os.clock()
  end
  function Profiler.count(name, amount)
    if not enabled then
      return
    end
    local item = samples[name]
    if not item then
      local size = 0
      for _ in pairs(samples) do
        size += 1
      end
      if size >= LIMIT then
        return
      end
      item = { calls = 0, total = 0, maximum = 0 }
      samples[name] = item
    end
    item.calls += amount or 1
  end
  function Profiler.finish(name, started)
    if not started then
      return
    end
    if debug.profileend then
      debug.profileend()
    end
    if not enabled then
      return
    end
    local item = samples[name]
    if not item then
      local count = 0
      for _ in pairs(samples) do
        count += 1
      end
      if count >= LIMIT then
        return
      end
      item = { calls = 0, total = 0, maximum = 0 }
      samples[name] = item
    end
    local elapsed = os.clock() - started
    item.calls += 1
    item.total += elapsed
    item.maximum = math.max(item.maximum, elapsed)
  end
  function Profiler.getStatus()
    local result = {}
    for name, item in pairs(samples) do
      result[name] = table.clone(item)
    end
    return { enabled = enabled, samples = result }
  end
  function Profiler.teardown()
    enabled = false
    table.clear(samples)
  end
  Profiler.__contract = {
    access = {
      default = "diagnostics.write",
      methods = {
        getStatus = "internal.read",
        isEnabled = "internal.read",
        setEnabled = "infrastructure.write",
      },
    },
    requires = {},
    provides = { "setup", "teardown", "setEnabled", "isEnabled", "begin", "finish", "count", "getStatus" },
  }
  return Profiler
end)()

return { __bundle = { status = __part_status, diagnostics = __part_diagnostics, profiler = __part_profiler } }
