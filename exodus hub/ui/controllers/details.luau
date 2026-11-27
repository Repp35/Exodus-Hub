-- [[ generic readout data binding ]]
--!optimize 2
-- @modules uidetails
local Details = {}
function Details.setup() return true end
function Details.create(context)
  local previous, reported = {}, {}
  local function refresh()
    local ok, values = pcall(context.deps.Information.snapshot)
    if not ok or type(values) ~= "table" then
      return
    end
    local keys = table.clone(previous)
    for key in pairs(values) do
      keys[key] = true
    end
    for key in pairs(keys) do
      if context.pages.getReadout(key) then
        local rendered, reason = pcall(context.pages.setReadout, key, values[key])
        if not rendered and not reported[key] then
          warn("[Exodus Readout] " .. tostring(reason))
        end
        reported[key] = not rendered
      end
    end
    previous = {}
    for key in pairs(values) do
      previous[key] = true
    end
    context.pages.refresh()
  end
  refresh()
  local elapsed = 0
  context.scope.connect(context.services.RunService.Heartbeat, function(dt)
    elapsed += dt
    if elapsed >= 0.5 and context.state.panelOpen then
      elapsed = 0
      refresh()
    end
  end)
  return {}
end
Details.__contract = { provides = { "setup", "create" }, requires = {} }
return Details
