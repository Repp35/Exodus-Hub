-- [[ adapter ]]

-- code
local Adapter = {}
local hub
function Adapter.setup(deps)
  hub = deps.Hub; return true
end
function Adapter.isAvailable() return hub.isNativeVisualAvailable() end
function Adapter.create(...) return hub.createVisualAdapter(...) end
function Adapter.apply(...) return hub.applyVisualPolicy(...) end
Adapter.__contract = {
  provides = { "setup", "create", "apply", "isAvailable" },
  requires = { Hub = "hubapi" },
  requiresMethods = { Hub = { "createVisualAdapter", "applyVisualPolicy", "isNativeVisualAvailable" } },
}

return Adapter
