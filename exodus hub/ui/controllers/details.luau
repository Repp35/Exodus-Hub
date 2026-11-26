-- [[ details ]]
--!optimize 2
-- @modules uidetails

local Details = {}
function Details.setup() return true end
function Details.create(context)
  local reported = {}
  local function refresh()
    local ok, values = pcall(context.deps.Information.snapshot)
    if not ok or type(values) ~= "table" then
      values = { session = "Informações temporariamente indisponíveis. Tentando novamente…" }
    end
    for _, key in ipairs({ "session", "game", "server", "versions", "developers" }) do
      local rendered, reason = pcall(context.pages.setReadout, key, values[key])
      if not rendered and not reported[key] then
        warn("[Exodus Information] " .. tostring(reason))
      end
      reported[key] = not rendered
    end
    context.pages.refresh()

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
