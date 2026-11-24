-- [[ camera ]]

-- code
local __part_camera = (function()
  local Camera = {}
  local utils
  local cameraEpoch = 0
  local cameraInput
  local cameraOriginal
  local cameraWrapped
  local configConnection
  local sensitivity = 1.5
  local CONFIG = {
    DEFAULT_SENSITIVITY = 1.5,
    MODULE_SEARCH_RETRY = 0.5,
  }

  local function normalizeSensitivity(value)
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value == math.huge then return CONFIG.DEFAULT_SENSITIVITY end
    return value
  end
  local function stopCamera()
    cameraEpoch += 1
    if cameraInput and cameraInput.getRotation == cameraWrapped then cameraInput.getRotation = cameraOriginal end
    if configConnection then
      if utils then utils.untrackGlobal(configConnection) end
      configConnection:Disconnect(); configConnection = nil
    end
    cameraInput, cameraOriginal, cameraWrapped = nil, nil, nil
  end
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
end)()
local __part_infinitezoom = (function()
  local InfiniteZoom = {}
  local utils
  local configObserver
  local zoomConnection
  local player
  local savedMaximum
  local enabled = false; local writing = false
  local CONFIG = {
    schema = { UniversalInfiniteZoom = "boolean" },
    defaults = { UniversalInfiniteZoom = false },
    MAX_DISTANCE = 1000000,
  }

  local function stop()
    enabled = false
    if zoomConnection then zoomConnection:Disconnect(); zoomConnection = nil end
    if player and savedMaximum ~= nil then
      local ok, reason = pcall(function() player.CameraMaxZoomDistance = savedMaximum end)
      if not ok then return false, tostring(reason) end
    end
    player, savedMaximum = nil, nil; return true
  end
  local function start()
    local target = utils.getLocalPlayer()
    if not target then return false, "LocalPlayer indisponível" end
    local ok, original = pcall(function() return target.CameraMaxZoomDistance end)
    if not ok then return false, "limite da câmera indisponível" end
    player, savedMaximum, enabled = target, original, true
    local function apply()
      if not enabled or writing then return end
      writing = true
      local applied, reason = pcall(function() player.CameraMaxZoomDistance = CONFIG.MAX_DISTANCE end)
      writing = false
      if not applied then return false, tostring(reason) end
      return true
    end
    local success, reason = apply()
    if not success then stop(); return false, reason end
    local connected, connection = pcall(function() return target:GetPropertyChangedSignal("CameraMaxZoomDistance"):Connect(apply) end)
    if not connected then stop(); return false, tostring(connection) end
    zoomConnection = connection; return true
  end
  local function applyEnabled(value)
    if value == enabled then return true end
    if value then return start() end
    return stop()
  end
  function InfiniteZoom.setEnabled(value)
    if not utils then return false, "recurso indisponível" end
    value = value == true; local ok, reason = applyEnabled(value)
    if not ok then return false, reason end
    if not utils.setConfig({ UniversalInfiniteZoom = value }) then applyEnabled(not value); return false, "configuração rejeitada" end
    return true
  end
  function InfiniteZoom.teardown()
    if configObserver then configObserver:Disconnect(); configObserver = nil end
    local ok, reason = stop(); utils = nil
    return ok, reason
  end
  function InfiniteZoom.setup(deps)
    if type(deps) ~= "table" or type(deps.Utils) ~= "table" then return false, "dependência ausente: Utils" end
    InfiniteZoom.teardown(); utils = deps.Utils
    configObserver = utils.observeConfig(function(changes)
      if changes.UniversalInfiniteZoom ~= nil then
        local ok, reason = applyEnabled(changes.UniversalInfiniteZoom == true)
        if not ok then utils.recordError("InfiniteZoom", reason); utils.setConfig({ UniversalInfiniteZoom = false }) end
      end
    end)
    if utils.getConfigValue("UniversalInfiniteZoom") == true then return InfiniteZoom.setEnabled(true) end
    return true
  end
  InfiniteZoom.__config = CONFIG
  InfiniteZoom.__contract = {
    requires = { Utils = "utils" },
    requiresMethods = { Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "recordError" } },
    provides = { "setup", "teardown", "setEnabled" },
  }
  return InfiniteZoom
end)()
local __part_invisicam = (function()
  local Invisicam = {}
  local Utils
  local configObserver
  local applied = false
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
    if propertyOk or (cameraOk and cameraError == true) then applied = enabled == true; return true end
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
    if Utils and applied then ok, reason = applyMode(false) end
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
    if Utils.getConfigValue("UniversalInvisicam") == true then return applyMode(true) end
    return true
  end
  Invisicam.__config = CONFIG
  Invisicam.__contract = {
    requires = { Utils = "utils" },
    requiresMethods = { Utils = { "getConfigValue", "setConfig", "observeConfig", "getLocalPlayer", "recordError" } },
    provides = { "setup", "teardown", "setEnabled" },
  }
  return Invisicam
end)()

return { __bundle = { camera = __part_camera, infinitezoom = __part_infinitezoom, invisicam = __part_invisicam } }
