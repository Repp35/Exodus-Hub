-- [[ read-only information page ]]
--!optimize 2
-- @modules uidetails

local Details = {}
function Details.setup() return true end
function Details.create(context)
  local function refresh()
    for key, value in pairs(context.deps.Information.snapshot()) do
      local handle = context.pages.getReadout(key)
      if handle then
        handle.setValue(value)
      end
    end
  end
  refresh()
  local elapsed = 0
  context.trackConn(context.services.RunService.Heartbeat:Connect(function(dt)
    elapsed += dt
    if elapsed >= 0.5 and context.state.panelOpen and context.pages.state().id == "information" then
      elapsed = 0
      refresh()
    end
  end))
  return {}
end
Details.__contract = { provides = { "setup", "create" }, requires = {} }
return Details
