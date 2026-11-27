-- [[ mm2 visuals ]]
--!optimize 2

local Visuals = {}
local State, World, Markers, Utils
local scope, markers
local colors = {
  Murderer = Color3.fromRGB(239, 68, 68),
  Sheriff = Color3.fromRGB(59, 130, 246),
  Hero = Color3.fromRGB(250, 204, 21),
  Innocent = Color3.fromRGB(34, 197, 94),
  Gun = Color3.fromRGB(250, 204, 21),
  Coin = Color3.fromRGB(236, 72, 153),
}
function Visuals.setup(deps)
  State, World, Markers, Utils = deps.State, deps.World, deps.Markers, deps.Utils
  return true
end
function Visuals.bind(lifetime)
  Visuals.teardown()
  scope = lifetime.child()
end
function Visuals.teardown()
  if scope then
    scope.destroy()
  end
  scope, markers = nil, nil
end
function Visuals.step()
  if not scope or not scope.alive then
    return
  end
  local player = Utils.getLocalPlayer()
  local parent = player:FindFirstChildOfClass("PlayerGui")
  if not markers and parent then
    markers = Markers.create(parent, scope)
  end
  if not markers then
    return
  end
  if not Utils.isActive() or not Utils.getConfigValue("MM2ESP") then
    markers.clear()
    return
  end
  local retained = {}
  local self = State.live(player, false)
  local function mark(key, object, identity, username, position, color)
    local parts = {}
    if Utils.getConfigValue("MM2ESPIdentity") then
      parts[#parts + 1] = identity
    end
    if username and Utils.getConfigValue("MM2ESPUsername") then
      parts[#parts + 1] = username
    end
    if self and position and Utils.getConfigValue("MM2ESPDistance") then
      parts[#parts + 1] = tostring(math.floor((self.root.Position - position).Magnitude)) .. " studs"
    end
    retained[key] = true
    markers.update(key, object, table.concat(parts, " · "), color)
  end
  for _, target in ipairs(game:GetService("Players"):GetPlayers()) do
    if target == player and not Utils.getConfigValue("MM2ESPSelf") then
      continue
    end
    local snap = State.live(target, true)
    if not snap then
      continue
    end
    local role = snap.role
    if role == "Innocent" and State.tool(snap, "Gun", false) then
      role = "Hero"
    end
    local filter = role == "Hero" and "Sheriff" or role
    if filter and Utils.getConfigValue("MM2ESP" .. filter) then
      mark(target, snap.character, role, target.Name, snap.root.Position, colors[role] or colors.Innocent)
    end
  end
  local map = State.map()
  if Utils.getConfigValue("MM2ESPGun") and map then
    for gun in pairs(World.guns()) do
      if gun.Parent and gun:IsDescendantOf(map) then
        mark(gun, gun, "Gun", nil, World.position(gun), colors.Gun)
      end
    end
  end
  if Utils.getConfigValue("MM2ESPCoins") and self then
    local candidates = {}
    for coin in pairs(World.coins()) do
      if World.collectable(coin) then
        candidates[#candidates + 1] = coin
      end
    end
    table.sort(candidates, function(a, b) return (a.Position - self.root.Position).Magnitude < (b.Position - self.root.Position).Magnitude end)
    for index = 1, math.min(40, #candidates) do
      local coin = candidates[index]
      mark(coin, coin, tostring(coin:GetAttribute("CoinID") or "Coin"), nil, coin.Position, colors.Coin)
    end
  end
  markers.retain(retained)
end
Visuals.__contract = {
  provides = { "setup", "bind", "teardown", "step" },
  requires = { State = "mm2state", World = "mm2world", Markers = "uiworldmarkers", Utils = "utils" },
  requiresMethods = {
    State = { "live", "tool", "map" },
    World = { "guns", "position", "coins", "collectable" },
    Markers = { "create" },
    Utils = { "getLocalPlayer", "getConfigValue", "isActive" },
  },
}
return Visuals
