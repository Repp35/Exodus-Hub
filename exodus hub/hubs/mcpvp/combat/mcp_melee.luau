-- [[ mcpmelee ]]
--!optimize 2
local Melee = {}
local native, target, utils, tuning, units
local owner, cycle, selected, pending
local queuedManual, equipAt, apex, warnedManual = false, 0, 0.25, false
function Melee.setup(deps)
  native, target, utils, tuning, units = deps.Native, deps.Target, deps.Utils, deps.Options.tuning, deps.Units
  return true
end
function Melee.reset()
  native.finishCritical()
  owner, cycle, selected, pending = nil, nil, nil, nil
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
  cycle = { at = snap.now, phase = "takeoff", vertical = units.toBlocks(snap.root.AssemblyLinearVelocity.Y) }
  queuedManual = false
  native.requestJump(snap)
  return true
end
function Melee.manual(snap)
  bind(snap)
  if not utils.getConfigValue("MCAutoCrit") or native.blocked(snap) then
    return false
  end
  if not native.attackGateReady() and not warnedManual then
    warnedManual = true
    utils.recordError("mcpvp.critical.manual", "O executor não permite adiar o ataque nativo; o pulo manual sozinho não garante um crítico.")
  end
  queuedManual = true
  if grounded(snap) and native.readyAt(snap, snap.tool) - snap.now <= apex + 0.04 then
    return startJump(snap)
  end
  return true
end
function Melee.intercept(snap, direction)
  if not utils.isActive() or not utils.getConfigValue("MCAutoCrit") or native.blocked(snap) then
    return true
  end
  bind(snap)
  local kind = native.stats(snap.tool).type
  if snap.tool and not kind then
    return true
  end
  if grounded(snap) and native.crystalJumpRisk(snap) then
    pending = nil
    return true
  end
  if native.criticalReady(snap) and snap.now >= native.readyAt(snap, snap.tool) then
    native.prepareCritical(true)
    pending, queuedManual = nil, false
    cycle = cycle or { at = snap.now, vertical = units.toBlocks(snap.root.AssemblyLinearVelocity.Y) }
    cycle.phase = "land"
    target.manual(snap)
    return true
  end
  pending = { character = snap.character, tool = snap.tool, direction = direction, expires = snap.now + 2.5 }
  target.manual(snap)
  Melee.manual(snap)
  return false
end
function Melee.postSimulation(snap)
  if not pending then
    return
  end
  if not snap or not utils.getConfigValue("MCAutoCrit") or snap.character ~= pending.character or snap.tool ~= pending.tool or snap.now >= pending.expires then
    pending, queuedManual, cycle = nil, false, nil
    native.finishCritical()
    return
  end
  if native.blocked(snap) then
    return
  end
  local readyAt = native.readyAt(snap, snap.tool)
  local crystalException = grounded(snap) and native.crystalJumpRisk(snap)
  if snap.now < readyAt or not (crystalException or native.criticalReady(snap)) then
    return
  end
  if not crystalException then
    native.prepareCritical(true)
  end
  target.manual(snap)
  if native.replayAttack(snap, pending.direction) then
    pending, queuedManual = nil, false
    if cycle then
      cycle.phase = "land"
    end
  end
end
function Melee.preSimulation(snap)
  if not snap or not utils.getConfigValue("MCAutoCrit") or native.blocked(snap) then
    cycle, queuedManual, pending = nil, false, nil
    native.finishCritical()
    return
  end
  bind(snap)
  local ground = grounded(snap)
  if cycle then
    local vertical = units.toBlocks(snap.root.AssemblyLinearVelocity.Y)
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
      native.finishCritical()
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
  if not cycle and queuedManual and ground and native.readyAt(snap, snap.tool) - snap.now <= apex + 0.04 then
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
    cycle = { at = snap.now, phase = "air", vertical = units.toBlocks(snap.root.AssemblyLinearVelocity.Y) }
  end
  if snap.now < readyAt or not native.criticalReady(snap) then
    return false
  end
  native.prepareCritical(true)
  return true
end
function Melee.step(snap, chosen)
  bind(snap)
  if
    not utils.getConfigValue("MCAutoSword")
    or not chosen
    or native.blocked(snap)
    or units.distance(chosen.root.Position, snap.root.Position) > tuning.focusRangeBlocks
  then
    return false
  end
  local tool = native.findSword(snap)
  local stats = native.stats(tool)
  if pending then
    return false
  end
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
  provides = { "setup", "reset", "step", "manual", "preSimulation", "intercept", "postSimulation" },
  requires = { Native = "mcpnative", Target = "mcptarget", Utils = "utils", Options = "mcpoptions", Units = "mcpunits" },
  requiresMethods = {
    Units = { "distance", "toBlocks" },
    Native = {
      "blocked",
      "findSword",
      "stats",
      "equip",
      "prepareCritical",
      "requestJump",
      "crystalJumpRisk",
      "attack",
      "readyAt",
      "attackDirection",
      "finishCritical",
      "criticalReady",
      "attackGateReady",
      "replayAttack",
    },
    Target = { "noteAttack", "manual" },
    Utils = { "getConfigValue", "isActive", "recordError" },
  },
  requiresData = { Options = { "tuning" } },
}
return Melee
