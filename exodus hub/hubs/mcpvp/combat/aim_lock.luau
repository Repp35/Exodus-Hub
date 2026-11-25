-- [[ aimlock ]]
--!optimize 2
local Lock = {}
local native, utils
function Lock.setup(deps) native, utils = deps.Native, deps.Utils return true end
function Lock.step(snap, chosen, dt)
  if not utils.getConfigValue("MCAimLock") then return end
  if native.aerialMace(snap, chosen) then return end
  if game:GetService("UserInputService"):GetFocusedTextBox() or game:GetService("GuiService").MenuIsOpen then return end
  local close = native.canHit(snap, chosen)
  local weapon = native.findSword(snap)
  local reach = weapon and native.stats(weapon).reach or 9.6
  if (chosen.root.Position - snap.root.Position).Magnitude > reach * 6 then return end
  local camera = snap.camera
  local eye = camera.CFrame.Position
  local root = chosen.root.Position
  local closest = eye + camera.CFrame.LookVector * math.max(0, (root - eye):Dot(camera.CFrame.LookVector))
  local point = root + Vector3.new(math.clamp(closest.X - root.X, -0.26, 0.26), math.clamp(closest.Y - root.Y, -1.2, 1.6), math.clamp(closest.Z - root.Z, -0.26, 0.26))
  -- Check from the actual camera too: a wall must stop the camera pull immediately.
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  params.RespectCanCollide = true
  params.FilterDescendantsInstances = { snap.character, camera }
  local hit = workspace:Raycast(eye, point - eye, params)
  if hit and not hit.Instance:IsDescendantOf(chosen.character) then return end
  if not native.visible(snap, point, chosen.character) then return end
  local delta = point - eye
  if delta.Magnitude <= 0.01 then return end
  local angle = math.acos(math.clamp(camera.CFrame.LookVector:Dot(delta.Unit), -1, 1))
  local alpha = angle < 0.001 and 1 or math.min(1, math.rad(close and 720 or 600) * math.clamp(tonumber(utils.getConfigValue("MCAimStrength")) or 100, 0, 100) / 100 * math.clamp(dt or 1 / 60, 0, 1 / 30) / angle)
  camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eye, point), alpha)
end
Lock.__contract = {
  provides = { "setup", "step" },
  requires = { Native = "mcpnative", Utils = "utils" },
  requiresMethods = { Native = { "aerialMace", "canHit", "findSword", "stats", "visible" }, Utils = { "getConfigValue" } },
}
return Lock
