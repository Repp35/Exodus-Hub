-- [[ camera sensitivity ]]

-- module
local Camera = {}
local utils
local cameraEpoch = 0
local cameraInput, cameraOriginal, cameraWrapped, configConnection
local sensitivity = 1.5

-- configuration
local CONFIG = {
  DEFAULT_SENSITIVITY = 1.5,
  MODULE_SEARCH_RETRY = 0.5,
}

local function normalizeSensitivity(value)
  value = tonumber(value)
  if not value or value ~= value or value < 0 or value == math.huge then return CONFIG.DEFAULT_SENSITIVITY end
  return value
end

-- camera-hook
local function stopCamera()
  cameraEpoch += 1
  if cameraInput and cameraInput.getRotation == cameraWrapped then cameraInput.getRotation = cameraOriginal end
  if configConnection then
    if utils then utils.untrackGlobal(configConnection) end
    configConnection:Disconnect(); configConnection = nil
  end
  cameraInput, cameraOriginal, cameraWrapped = nil, nil, nil
end

-- camera-watcher
local function startCamera()
  stopCamera(); local token = cameraEpoch
  task.spawn(function()
    while token == cameraEpoch and utils and utils.isActive() do
      local player = utils.getLocalPlayer(); local scripts = player and player:FindFirstChild("PlayerScripts")
      local module = scripts and scripts:FindFirstChild("PlayerModule"); local camera = module and module:FindFirstChild("CameraModule")
      local input = camera and camera:FindFirstChild("CameraInput")
      if input and input:IsA("ModuleScript") then
        local loaded, api = pcall(require, input)
        if token ~= cameraEpoch or not utils then return end
        if loaded and type(api) == "table" and type(api.getRotation) == "function" then
          cameraInput, cameraOriginal = api, api.getRotation; local original, boundUtils = cameraOriginal, utils
          local wrapped
          wrapped = function(...)
            local rotation = original(...)
            if token ~= cameraEpoch or utils ~= boundUtils or not boundUtils.isActive() then
              if api.getRotation == wrapped then api.getRotation = original end
              return rotation
            end
            return rotation * sensitivity
          end
          cameraWrapped = wrapped; cameraInput.getRotation = cameraWrapped
          return
        end
      end
      task.wait(CONFIG.MODULE_SEARCH_RETRY)
    end
  end)
end

-- setup
function Camera.setup(deps)
  if type(deps) ~= "table" or type(deps.Utils) ~= "table" then return false, "dependência ausente: Utils" end
  Camera.teardown(); utils = deps.Utils
  sensitivity = normalizeSensitivity(utils.getConfigValue("CameraSensitivity")); startCamera()
  configConnection = utils.observeConfig(function(changes)
    if changes.CameraSensitivity ~= nil then sensitivity = normalizeSensitivity(changes.CameraSensitivity) end
  end)
  utils.trackGlobal(configConnection); return true
end
function Camera.teardown()
  stopCamera(); utils = nil
end

-- contract
Camera.__contract = {
  requires = { Utils = "utils" },
  requiresMethods = {
    Utils = {
      "getLocalPlayer",
      "getConfigValue",
      "isActive",
      "observeConfig",
      "trackGlobal",
      "untrackGlobal",
    },
  },
  provides = { "setup", "teardown" },
}

return Camera
