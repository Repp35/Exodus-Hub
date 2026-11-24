-- [[ resource lifetime ]]
-- @modules lifetime

-- code
local Lifetime = {}
function Lifetime.setup() return true end
function Lifetime.scope()
  local scope = { alive = true }
  local resources, last = {}, nil
  local function unlink(resource)
    local entry = resources[resource]
    if not entry then
      return nil
    end
    resources[resource] = nil
    if entry.previous then
      entry.previous.next = entry.next
    end
    if entry.next then
      entry.next.previous = entry.previous
    else
      last = entry.previous
    end
    return entry.cleanup
  end
  function scope.add(resource, dispose)
    local cleanup = dispose
      or function()
        if type(resource) == "function" then
          resource()
        else
          resource:Disconnect()
        end
      end
    if not scope.alive then
      cleanup()
      return resource
    end
    if resources[resource] then
      return resource
    end
    local entry = { resource = resource, cleanup = cleanup, previous = last }
    if last then
      last.next = entry
    end
    resources[resource], last = entry, entry
    return resource
  end
  function scope.forget(resource) unlink(resource) end
  function scope.remove(resource)
    local cleanup = unlink(resource)
    if cleanup then
      cleanup()
    end
  end
  function scope.connect(signal, callback)
    return scope.add(signal:Connect(function(...)
      if scope.alive then
        callback(...)
      end
    end))
  end
  function scope.child()
    local child = Lifetime.scope()
    scope.add(child, child.destroy)
    child.add(function() scope.forget(child) end)
    return child
  end
  function scope.destroy()
    if not scope.alive then
      return
    end
    scope.alive = false
    while last do
      local cleanup = unlink(last.resource)
      local ok, reason = pcall(cleanup)
      if not ok then
        warn("[Exodus] Cleanup failed: " .. tostring(reason))
      end
    end
  end
  return scope
end
function Lifetime.connections(utils)
  local scope = Lifetime.scope()
  local pool = { connections = {} }
  function pool.disconnect(name)
    local connection = pool.connections[name]
    pool.connections[name] = nil
    if connection then
      scope.remove(connection)
    end
  end
  function pool.connect(name, signal, callback)
    pool.disconnect(name)
    local connection = signal:Connect(callback)
    pool.connections[name] = connection
    utils.trackGlobal(connection)
    scope.add(connection, function()
      utils.untrackGlobal(connection)
      connection:Disconnect()
    end)
    return connection
  end
  function pool.destroy()
    scope.destroy()
    table.clear(pool.connections)
  end
  return pool
end
Lifetime.__contract = {
  access = { default = "lifetime.manage" },
  requires = {},
  provides = { "setup", "scope", "connections" },
}

return Lifetime
