-- [[ assists ]]
--!optimize 2
-- @modules uiassists
local Assists = {}
function Assists.setup() return true end
function Assists.create(context)
  local utils, gameInfo = context.deps.Utils, context.deps.Hub
  local elapsed, automatic = 0, {}
  local function refresh()
    local rules = not context.state.desktop and gameInfo.getMiniVisibility() or {}
    local changed = false
    for key, visible in pairs(rules) do
      if automatic[key] ~= visible then
        changed = true
      end
    end
    for key in pairs(automatic) do
      if rules[key] == nil then
        changed = true
      end
    end
    if changed then
      automatic = rules
      context.floating.applyVisibility(rules)
    end
  end
  context.trackConn(context.services.RunService.Heartbeat:Connect(function(dt)
    elapsed += dt
    if elapsed >= 0.1 then
      elapsed = 0
      refresh()
    end
  end))
  context.scope.add(utils.observeConfig(function()
    automatic = {}
    refresh()
  end))
  refresh()
  return {}
end
Assists.__contract = { provides = { "setup", "create" }, requires = {} }
return Assists
