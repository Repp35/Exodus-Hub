-- [[ invisicam ]]

-- code
local Invisicam = {}
local Utils, configObserver
local CONFIG = {
  schema = { UniversalInvisicam = "boolean" },
  defaults = { UniversalInvisicam = false },
}

local function applyMode(enabled)
  local player = Utils and Utils.getLocalPlayer()
  if not player then return false, "LocalPlayer unavailable" end
  local mode = enabled and Enum.DevCameraOcclusionMode.Invisicam or Enum.DevCameraOcclusionMode.Zoom
  local propertyOk, propertyError = pcall(function() player.DevCameraOcclusionMode = mode end)
  local cameraOk, cameraError = pcall(function()
    local scripts = player:FindFirstChild("PlayerScripts"); local module = scripts and scripts:FindFirstChild("PlayerModule")
    if not module then return false end
    local api = require(module); local cameras = type(api) == "table" and type(api.GetCameras) == "function" and api:GetCameras()
    if not cameras or type(cameras.ActivateOcclusionModule) ~= "function" then return false end
    cameras:ActivateOcclusionModule(mode); return true
  end)
  if propertyOk or (cameraOk and cameraError == true) then return true end
  return false, tostring(propertyError or cameraError)
end
function Invisicam.setEnabled(enabled)
  if not Utils then return false, "feature unavailable" end
  local value = enabled == true; local ok, reason = applyMode(value)
  if not ok then return false, reason end
  return Utils.setConfig({ UniversalInvisicam = value })
end
function Invisicam.teardown()
  if configObserver then configObserver:Disconnect(); configObserver = nil end
  local ok, reason = true, nil
  if Utils then ok, reason = applyMode(false) end
  Utils = nil; return ok, reason
end
function Invisicam.setup(deps)
  if type(deps) ~= "table" or type(deps.Utils) ~= "table" then return false, "missing dependency: Utils" end
  Invisicam.teardown(); Utils = deps.Utils
  configObserver = Utils.observeConfig(function(changes)
    if changes.UniversalInvisicam ~= nil then
      local ok, reason = applyMode(changes.UniversalInvisicam == true)
      if not ok then Utils.recordError("Invisicam", reason) end
    end
  end)
  return applyMode(Utils.getConfigValue("UniversalInvisicam") == true)
end
Invisicam.__config = CONFIG
Invisicam.__contract = {
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "recordError" } },
  provides = { "setup", "teardown", "setEnabled" },
}

return Invisicam
