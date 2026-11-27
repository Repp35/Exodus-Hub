-- [[ mm2 farm ]]
--!optimize 2

local Farm = {}
local State, World, Movement, Utils
local target, startedAt, nextPick = nil, 0, 0
local ignored = setmetatable({}, { __mode = "k" })
function Farm.setup(deps)
  State, World, Movement, Utils = deps.State, deps.World, deps.Movement, deps.Utils
  return true
end
function Farm.reset()
  target, nextPick = nil, 0
  ignored = setmetatable({}, { __mode = "k" })
  Movement.cancel("farm")
end
function Farm.step(snap)
  if not Utils.getConfigValue("MM2AutoFarm") or not snap or State.full() then
    Farm.reset()
    if snap and State.full() and snap.role == "Innocent" and Utils.getConfigValue("MM2ResetFull") then
      snap.humanoid.Health = 0
    end
    return
  end
  local owner = Movement.owner()
  if owner and owner ~= "farm" then
    return
  end
  local now = os.clock()
  if target and (not World.collectable(target) or now - startedAt > 8) then
    ignored[target] = now + 4
    target = nil
    Movement.cancel("farm")
  end
  if not target then
    if now < nextPick then
      return
    end
    nextPick = now + 0.35
    local murderer = Utils.getConfigValue("MM2AvoidMurderer") and State.findRole("Murderer")
    target = World.nearest(
      snap.root.Position,
      World.coins(),
      function(coin)
        return (ignored[coin] or 0) <= now and World.collectable(coin) and (not murderer or (coin.Position - murderer.root.Position).Magnitude >= 18)
      end
    )
    startedAt = now
  end
  if target then
    Movement.walk(snap, target.Position, "farm", Utils.getConfigValue("MM2FarmSpeed"))
  end
end
Farm.__contract = {
  provides = { "setup", "reset", "step" },
  requires = { State = "mm2state", World = "mm2world", Movement = "mm2movement", Utils = "utils" },
  requiresMethods = {
    State = { "full", "findRole" },
    World = { "collectable", "nearest", "coins" },
    Movement = { "owner", "walk", "cancel" },
    Utils = { "getConfigValue" },
  },
}
return Farm
