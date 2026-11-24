-- [[ runtime ]]

-- code
local Runtime = {}
function Runtime.setup() return true end
function Runtime.bind(loaded, ...)
  if loaded.gameruntime then return loaded.gameruntime.bind(loaded, ...) end
  return {
    mode = loaded.gamecontext.getProfile().id,
    parryRemote = false,
    parryInitialized = false,
    watcher = false,
    ballSync = false,
    maintenance = false,
    ballSyncSubscribers = 0,
  }
end
Runtime.__contract = { provides = { "setup", "bind" }, requires = {} }

return Runtime
