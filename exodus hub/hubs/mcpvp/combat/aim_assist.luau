-- [[ aimassist ]]
--!optimize 2
local Assist = {}
local native, utils
function Assist.setup(deps) native, utils = deps.Native, deps.Utils return true end
function Assist.step(snap, chosen, dt)
  if not utils.getConfigValue("MCAimAssist") then return end
  local input = game:GetService("UserInputService")
  if input:GetFocusedTextBox() or game:GetService("GuiService").MenuIsOpen or native.blocked(snap) then return end
  if (chosen.root.Position - snap.root.Position).Magnitude > 16 then return end
  local point = chosen.root.Position + Vector3.new(0, chosen.character:GetAttribute("Sneaking") == true and 0.15 or 0.5, 0)
  local eye, look = snap.camera.CFrame.Position, snap.camera.CFrame.LookVector
  local delta = point - eye
  if delta.Magnitude < 0.1 then return end
  local angle = math.acos(math.clamp(look:Dot(delta.Unit), -1, 1))
  if angle > math.rad(12) or angle < math.rad(0.35) then return end
  local params = RaycastParams.new()
  params.FilterType, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
  params.FilterDescendantsInstances = { snap.character, snap.camera }
  local hit = workspace:Raycast(eye, delta, params)
  if hit and not hit.Instance:IsDescendantOf(chosen.character) or not native.visible(snap, point, chosen.character) then return end
  -- MobileAimAssist.Step's gamepad profile from the dump, independent of the attack module.
  local elapsed = math.clamp(dt or 1 / 60, 0, 1 / 15)
  local strength = math.clamp(tonumber(utils.getConfigValue("MCAimStrength")) or 100, 0, 100) / 100
  local turn = math.min(angle * (1 - math.exp(-2.5 * elapsed)), math.rad(20) * elapsed) * strength
  local axis = look:Cross(delta.Unit)
  if axis.Magnitude < 0.000001 then return end
  local direction = CFrame.fromAxisAngle(axis.Unit, turn):VectorToWorldSpace(look)
  snap.camera.CFrame = CFrame.lookAt(eye, eye + direction)
end
Assist.__contract = {
  provides = { "setup", "step" },
  requires = { Native = "mcpnative", Utils = "utils" },
  requiresMethods = { Native = { "blocked", "visible" }, Utils = { "getConfigValue" } },
}
return Assist
