--!optimize 2
-- @modules runtime

local Runtime = {}
function Runtime.setup() return true end
function Runtime.bind(loaded, ...)
  if loaded.gameruntime then
    local boundary = loaded.gamescope.create(loaded, loaded.gamecontext.getProfile())
    return loaded.gameruntime.bind(boundary.modules, ...)
  end
  return {
    mode = loaded.gamecontext.getProfile().id,
  }
end
Runtime.__contract = { provides = { "setup", "bind" }, requires = {} }
return Runtime
