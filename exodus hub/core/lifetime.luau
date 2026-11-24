-- [[ resource lifetime ]]

-- code
local Lifetime = {}
function Lifetime.setup() return true end
function Lifetime.scope()
  local scope = { alive = true }; local resources = {}
  function scope.add(resource, dispose)
    local cleanup = dispose or function()
      if type(resource) == "function" then resource() else resource:Disconnect() end
    end
    if not scope.alive then cleanup(); return resource end
    resources[resource] = cleanup; return resource
  end
  function scope.forget(resource) resources[resource] = nil end
  function scope.remove(resource)
    local cleanup = resources[resource]; resources[resource] = nil
    if cleanup then cleanup() end
  end
  function scope.connect(signal, callback)
    return scope.add(signal:Connect(function(...)
      if scope.alive then callback(...) end
    end))
  end
  function scope.child()
    local child = Lifetime.scope(); scope.add(child, child.destroy)
    child.add(function() scope.forget(child) end)
    return child
  end
  function scope.destroy()
    if not scope.alive then return end
    scope.alive = false; local pending = resources
    resources = {}
    for _, cleanup in pairs(pending) do
      local ok, reason = pcall(cleanup)
      if not ok then warn("[Exodus] Cleanup failed: " .. tostring(reason)) end
    end
  end
  return scope
end
function Lifetime.connections(utils)
  local scope = Lifetime.scope(); local pool = { connections = {} }
  function pool.disconnect(name)
    local connection = pool.connections[name]; pool.connections[name] = nil
    if connection then scope.remove(connection) end
  end
  function pool.connect(name, signal, callback)
    pool.disconnect(name); local connection = signal:Connect(callback)
    pool.connections[name] = connection; utils.trackGlobal(connection)
    scope.add(connection, function()
      utils.untrackGlobal(connection); connection:Disconnect()
    end)
    return connection
  end
  function pool.destroy()
    scope.destroy(); table.clear(pool.connections)
  end
  return pool
end
Lifetime.__contract = {
  access = { default = "lifetime.manage" },
  requires = {},
  provides = { "setup", "scope", "connections" },
}

return Lifetime
