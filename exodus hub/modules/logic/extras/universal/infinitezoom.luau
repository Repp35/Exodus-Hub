-- [[ infinite zoom ]]

-- code
local InfiniteZoom = {}
local utils, configObserver, zoomConnection, player, savedMaximum
local enabled, writing = false, false
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
