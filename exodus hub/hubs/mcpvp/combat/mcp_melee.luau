-- [[ mcpmelee ]]
--!optimize 2
local Melee = {}
local native, geometry, target, utils
local cycle, retryAt = nil, 0
local function enabled(key) return utils.getConfigValue(key) == true end
function Melee.setup(deps)
  native, geometry, target, utils = deps.Native, deps.Geometry, deps.Target, deps.Utils
  return true
end
function Melee.reset()
  local snap = native.snapshot()
  if snap then
    native.sprint(snap, false)
  end
  cycle, retryAt = nil, 0
end
function Melee.request(snap, chosen)
  if not chosen or not enabled("MCAutoCrit") then
    return false
  end
  if cycle and cycle.chosen.id == chosen.id and cycle.tool == snap.tool then
    cycle.manual = true
    return true
  end
  cycle = { chosen = chosen, character = snap.character, tool = snap.tool, manual = true, at = snap.now, phase = geometry.grounded(snap) and "ready" or "air" }
  return true
end
local function chosen(snap)
  if cycle and (cycle.character ~= snap.character or not target.isCurrent(snap, cycle.chosen) or snap.now - cycle.at > 2) then
    Melee.reset()
  end
  if cycle then
    return cycle.chosen
  end
  return enabled("MCAutoSword") and target.near(snap) or nil
end
function Melee.prepare(snap)
  local value = chosen(snap)
  if not value or native.blocked(snap) or snap.now < retryAt then
    return
  end
  local tool
  if cycle and cycle.manual then
    tool = snap.tool
  else
    tool = native.find(snap, "sword")
  end
  if not tool and not (cycle and cycle.manual) or not geometry.direction(snap, value, tool) then
    return
  end
  if snap.tool ~= tool then
    native.equip(snap, tool)
    return
  end
  if not enabled("MCAutoCrit") then
    return
  end
  local speed = geometry.stats(tool).speed or 1.6
  if not cycle then
    if native.charge(snap) + speed * 0.28 < 1 then
      return
    end
    cycle = { chosen = value, character = snap.character, tool = tool, at = snap.now, phase = geometry.grounded(snap) and "ready" or "air" }
  end
  if cycle.tool and cycle.tool ~= tool then
    Melee.reset()
    return
  end
  cycle.tool = tool
  if cycle.phase == "ready" then
    if native.charge(snap) + speed * 0.28 < 1 then
      return
    end
    if geometry.jumpRisk(snap) then
      cycle.phase = "ground"
      return
    end
    native.sprint(snap, true)
    if native.jump(snap) then
      cycle.phase, cycle.jumpAt = "jump", snap.now
    end
  elseif cycle.phase == "jump" then
    if not geometry.grounded(snap) then
      cycle.phase = "air"
    elseif snap.now - cycle.jumpAt > 0.6 then
      cycle.phase = "ground"
    end
  elseif cycle.phase == "air" and geometry.grounded(snap) then
    -- A missed fall window must not leave the attack permanently pending.
    cycle.phase = cycle.jumpAt and "ground" or "ready"
  end
  if cycle.phase == "air" or cycle.phase == "jump" then
    native.sprint(snap, true)
  end
end
function Melee.strike(snap)
  local value = chosen(snap)
  if not value or native.blocked(snap) or snap.now < retryAt then
    return
  end
  local tool
  if cycle then
    tool = cycle.tool
  else
    tool = native.find(snap, "sword")
  end
  if not tool and not (cycle and cycle.manual) or snap.tool ~= tool then
    return
  end
  local direction = geometry.direction(snap, value, tool)
  if not direction then
    if cycle then
      Melee.reset()
    end
    return
  end
  if enabled("MCAutoCrit") then
    if not cycle then
      return
    end
    if cycle.phase == "jump" and not geometry.grounded(snap) then
      cycle.phase = "air"
    end
    local charged = native.charge(snap) + (geometry.stats(tool).speed or 1.6) * 0.025 >= 1
    if not charged or not (cycle.phase == "ground" or geometry.falling(snap)) then
      return
    end
    -- Stop sprint immediately before the native attack; do not wait for replicated request flags.
    native.sprint(snap, true, true)
  end
  if native.attack(snap, value, direction) then
    target.attacked(snap, value)
    native.sprint(snap, false)
    cycle, retryAt = nil, snap.now + 1 / 7
  end
end
Melee.__contract = {
  provides = { "setup", "reset", "request", "prepare", "strike" },
  requires = { Native = "mcpnative", Geometry = "mcpgeometry", Target = "mcptarget", Utils = "utils" },
  requiresMethods = {
    Native = { "snapshot", "sprint", "blocked", "find", "equip", "charge", "jump", "attack" },
    Geometry = { "grounded", "direction", "stats", "jumpRisk", "falling" },
    Target = { "isCurrent", "near", "attacked" },
    Utils = { "getConfigValue" },
  },
}
return Melee
