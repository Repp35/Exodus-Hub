-- [[ mm2 alerts ]]
--!optimize 2

local Alerts = {}
local State, World, Utils
local lastMap, signature, seen, notify = nil, nil, {}, nil
function Alerts.setup(deps)
  State, World, Utils = deps.State, deps.World, deps.Utils
  return true
end
function Alerts.bind(callback)
  notify = callback
  Alerts.reset()
end
function Alerts.reset()
  lastMap, signature, seen = nil, nil, {}
end
function Alerts.step()
  local map = State.map()
  if lastMap ~= map then
    lastMap, signature, seen = map, nil, {}
  end
  if not map then
    return
  end
  local snap = State.live(Utils.getLocalPlayer(), true)
  local murderer = State.findRole("Murderer")
  if snap and murderer and Utils.getConfigValue("MM2AlertRoles") then
    local nextSignature = tostring(snap.role) .. "|" .. murderer.player.Name
    if
      nextSignature ~= signature
      and notify("Papéis da rodada", "Seu cargo: " .. tostring(snap.role) .. " · Assassino: " .. murderer.player.DisplayName, { id = "mm2-roles" })
    then
      signature = nextSignature
    end
  end
  for gun in pairs(seen) do
    if not World.guns()[gun] then
      seen[gun] = nil
    end
  end
  for gun in pairs(World.guns()) do
    if not seen[gun] and gun:IsDescendantOf(map) then
      if not Utils.getConfigValue("MM2AlertGun") or notify("Arma caiu", "Uma arma está disponível no mapa.", { id = "mm2-gun", kind = "warning" }) then
        seen[gun] = true
      end
    end
  end
end
Alerts.__contract = {
  provides = { "setup", "bind", "reset", "step" },
  requires = { State = "mm2state", World = "mm2world", Utils = "utils" },
  requiresMethods = { State = { "map", "live", "findRole" }, World = { "guns" }, Utils = { "getConfigValue", "getLocalPlayer" } },
}
return Alerts
