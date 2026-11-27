-- [[ mm2 pickup ]]
--!optimize 2

local Pickup = {}
local State, World, Movement, Utils
local nextTeleport = 0
function Pickup.setup(deps)
  State, World, Movement, Utils = deps.State, deps.World, deps.Movement, deps.Utils
  return true
end
function Pickup.reset()
  nextTeleport = 0
  Movement.cancel("pickup")
end
function Pickup.step(snap)
  if
    not snap
    or snap.role == "Murderer"
    or State.tool(snap, "Gun", false)
    or not Utils.getConfigValue("MM2AutoPickup") and not Utils.getConfigValue("MM2TeleportGun")
  then
    Pickup.reset()
    return false
  end
  if Movement.owner() == "manual" then
    return false
  end
  local map = State.map()
  local _, point = World.nearest(snap.root.Position, World.guns(), function(object) return map ~= nil and object:IsDescendantOf(map) end)
  if not point then
    Pickup.reset()
    return false
  end
  local murderer = Utils.getConfigValue("MM2PickupSafety") and State.findRole("Murderer")
  if murderer and ((murderer.root.Position - point).Magnitude < 20 or (murderer.root.Position - snap.root.Position).Magnitude < 12) then
    Pickup.reset()
    return false
  end
  if Utils.getConfigValue("MM2TeleportGun") then
    if os.clock() >= nextTeleport then
      nextTeleport = os.clock() + 1
      Movement.teleport(snap, point + Vector3.new(0, 2, 0))
    end
  else
    Movement.walk(snap, point, "pickup")
  end
  return true
end
Pickup.__contract = {
  provides = { "setup", "reset", "step" },
  requires = { State = "mm2state", World = "mm2world", Movement = "mm2movement", Utils = "utils" },
  requiresMethods = {
    State = { "map", "tool", "findRole" },
    World = { "nearest", "guns" },
    Movement = { "cancel", "owner", "teleport", "walk" },
    Utils = { "getConfigValue" },
  },
}
return Pickup
