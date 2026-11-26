-- [[ mcpaim ]]
--!optimize 2
local Aim = {}
local native, utils, tuning, units
local input, gui
function Aim.setup(deps)
  native, utils, tuning, units = deps.Native, deps.Utils, deps.Options.tuning, deps.Units
  input, gui = game:GetService("UserInputService"), game:GetService("GuiService")
  return true
end
function Aim.step(snap, target, dt)
  local lock, assist = utils.getConfigValue("MCAimLock"), utils.getConfigValue("MCAimAssist")
  if not (lock or assist) or input:GetFocusedTextBox() or gui.MenuIsOpen or native.blocked(snap) then
    return
  end
  local strength = math.clamp(tonumber(utils.getConfigValue("MCAimStrength")) or 100, 0, 100) / 100
  if strength == 0 then
    return
  end
  local camera, root = snap.camera, target.root.Position
  local eye, look = camera.CFrame.Position, camera.CFrame.LookVector
  local range = tuning.focusRangeBlocks
  if units.distance(root, snap.root.Position) > range then
    return
  end
  -- Aim at the current body position, without leading or projecting target motion.
  local point = root + units.offset(0, target.character:GetAttribute("Sneaking") == true and 3 / 64 or 5 / 32, 0)
  local delta = point - eye
  if units.toBlocks(delta).Magnitude < 1 / 320 then
    return
  end
  local direction = delta.Unit
  local angle = math.acos(math.clamp(look:Dot(direction), -1, 1))
  if angle < 0.001 or not lock and angle > math.rad(12) then
    return
  end
  if not native.visible(snap, point, target.character, eye) or not native.visible(snap, point, target.character) then
    return
  end
  local elapsed = math.clamp(dt or 1 / 60, 0, 1 / 15)
  local response = lock and 24 or 2.5
  local turn = math.min(angle * (1 - math.exp(-response * elapsed)), math.rad(lock and 720 or 20) * elapsed) * strength
  local axis = look:Cross(direction)
  if axis.Magnitude < 1e-6 then
    axis = camera.CFrame.UpVector
  end
  -- Rotate the entire camera basis to preserve roll; one writer even when both modes are enabled.
  local rotation = CFrame.fromAxisAngle(axis.Unit, turn)
  camera.CFrame = CFrame.new(eye) * rotation * camera.CFrame.Rotation
end
Aim.__contract = {
  provides = { "setup", "step" },
  requires = { Native = "mcpnative", Utils = "utils", Options = "mcpoptions", Units = "mcpunits" },
  requiresData = { Options = { "tuning" } },
  requiresMethods = { Units = { "distance", "offset", "toBlocks" }, Native = { "blocked", "visible" }, Utils = { "getConfigValue" } },
}
return Aim
