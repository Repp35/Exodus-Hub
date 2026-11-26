-- [[ mcpmelee ]]
--!optimize 2
local Melee = {}
local native, target, utils, tuning
local owner, cycle, selected
local queuedManual, equipAt, apex = false, 0, 0.25
function Melee.setup(deps)
  native, target, utils, tuning = deps.Native, deps.Target, deps.Utils, deps.Options.tuning
  return true
end
function Melee.reset()
  owner, cycle, selected = nil, nil, nil
  queuedManual, equipAt, apex = false, 0, 0.25
end
local function grounded(snap)
  local value = snap.character:GetAttribute("VoxelGrounded")
  if type(value) == "boolean" then
    return value
  end
  return snap.humanoid.FloorMaterial ~= Enum.Material.Air
end
local function bind(snap)
  if owner ~= snap.character then
    Melee.reset()
    owner = snap.character
  end
end
local function startJump(snap)
  if native.crystalJumpRisk(snap) then
    cycle, queuedManual = nil, false
    return false
  end
  native.prepareCritical()
  cycle = { at = snap.now, phase = "takeoff", vertical = snap.root.AssemblyLinearVelocity.Y }
  queuedManual = false
  native.requestJump(snap)
  return true
end
function Melee.manual(snap)
  bind(snap)
  if not utils.getConfigValue("MCAutoCrit") or native.blocked(snap) then
    return false
  end
  queuedManual = true
  if grounded(snap) then
    return startJump(snap)
  end
  return true
end
function Melee.preSimulation(snap)
  if not snap or not utils.getConfigValue("MCAutoCrit") or native.blocked(snap) then
    cycle, queuedManual = nil, false
    return
  end
  bind(snap)
  local ground = grounded(snap)
  if cycle then
    local vertical = snap.root.AssemblyLinearVelocity.Y
    if cycle.phase == "takeoff" then
      if ground then
        -- Keep the request alive until the native movement actually leaves the ground.
        if native.crystalJumpRisk(snap) then
          cycle, queuedManual = nil, false
          return
        end
        native.requestJump(snap)
      else
        cycle.phase = "air"
      end
    elseif ground then
      cycle = nil
    end
    if cycle then
      if cycle.phase == "air" and cycle.vertical > 0 and vertical <= 0 then
        local measured = snap.now - cycle.at
        if measured >= 0.1 and measured <= 0.8 then
          apex = math.clamp((apex + measured) * 0.5, 0.1, 0.8)
        end
      end
      cycle.vertical = vertical
      if not ground then
        native.prepareCritical()
      end
    end
  end
  if not cycle and queuedManual and ground then
    startJump(snap)
  end
end
local function criticalReady(snap, readyAt)
  if not utils.getConfigValue("MCAutoCrit") then
    cycle, queuedManual = nil, false
    return snap.now >= readyAt
  end
  if grounded(snap) then
    if native.crystalJumpRisk(snap) then
      cycle, queuedManual = nil, false
      return snap.now >= readyAt
    end
    if not cycle and readyAt - snap.now <= apex + 0.04 then
      startJump(snap)
    end
    return false
  end
  -- Each automatic strike gets its own jump cycle; do not chain grounded fallbacks.
  if cycle and cycle.phase == "land" then
    return false
  end
  if not cycle then
    cycle = { at = snap.now, phase = "air", vertical = snap.root.AssemblyLinearVelocity.Y }
  end
  local fall = tonumber(snap.character:GetAttribute("LocalFallDistance")) or 0
  local falling = snap.root.AssemblyLinearVelocity.Y < -0.1 or fall > 0
  if not falling or snap.now < readyAt then
    return false
  end
  native.prepareCritical()
  return true
end
function Melee.step(snap, chosen)
  bind(snap)
  if
    not utils.getConfigValue("MCAutoSword")
    or not chosen
    or native.blocked(snap)
    or (chosen.root.Position - snap.root.Position).Magnitude > tuning.focusRange
  then
    return false
  end
  local tool = native.findSword(snap)
  local stats = native.stats(tool)
  if not tool or stats.type ~= "sword" or type(stats.speed) ~= "number" or stats.speed <= 0 then
    return false
  end
  if snap.tool ~= tool then
    if not native.attackDirection(snap, chosen, tool) then
      return false
    end
    if selected ~= tool or snap.now - equipAt >= 0.75 then
      if native.equip(snap, tool) then
        selected, equipAt = tool, snap.now
      end
    end
    return false
  end
  local readyAt = native.readyAt(snap, tool)
  local lead = utils.getConfigValue("MCAutoCrit") and apex + 0.04 or 0
  if not cycle and readyAt - snap.now > lead then
    return false
  end
  local direction = native.attackDirection(snap, chosen, tool)
  if not direction or not criticalReady(snap, readyAt) then
    return false
  end
  if not native.attack(snap, chosen, direction) then
    return false
  end
  target.noteAttack(snap, chosen)
  if utils.getConfigValue("MCAutoCrit") and cycle then
    cycle.phase = "land"
  end
  return true
end
Melee.__contract = {
  provides = { "setup", "reset", "step", "manual", "preSimulation" },
  requires = { Native = "mcpnative", Target = "mcptarget", Utils = "utils", Options = "mcpoptions" },
  requiresMethods = {
    Native = { "blocked", "findSword", "stats", "equip", "prepareCritical", "requestJump", "crystalJumpRisk", "attack", "readyAt", "attackDirection" },
    Target = { "noteAttack" },
    Utils = { "getConfigValue" },
  },
  requiresData = { Options = { "tuning" } },
}
return Melee
