-- [[ hubapi ]]

-- code
local HubAPI = {}
local modules = {}
function HubAPI.setup() return true end
function HubAPI.configure(loaded)
  modules = loaded; return true
end
function HubAPI.teardown()
  modules = {}; return true
end
function HubAPI.areAbilitiesEnabled() return modules.gameinfo ~= nil and modules.gameinfo.areAbilitiesEnabled() end
function HubAPI.getAbilityAvailability(name)
  if modules.gameinfo then return modules.gameinfo.getAbilityAvailability(name) end
  return false, "Recurso indisponível neste jogo"
end
function HubAPI.getGameContext() return modules.gameinfo and modules.gameinfo.getGameContext() or {} end
function HubAPI.observeAbilityMode(callback)
  if modules.gameinfo then return modules.gameinfo.observeAbilityMode(callback) end
  return { Disconnect = function() end }
end
function HubAPI.hasClashPrediction() return modules.autospam ~= nil and modules.autospam.hasClashPrediction() end
function HubAPI.createCrateNetwork() return modules.gameinfo and modules.gameinfo.createCrateNetwork() end
function HubAPI.spinCrate(...)
  if modules.gameinfo then return modules.gameinfo.spinCrate(...) end
  return false
end
function HubAPI.resetState()
  if modules.spam then modules.spam.resetState() end
end
function HubAPI.isNativeVisualAvailable() return modules.nativevisuals ~= nil end
function HubAPI.applyVisualPolicy(...)
  if modules.nativevisuals then return modules.nativevisuals.apply(...) end
  local _, target, watch = ...
  return target, watch
end
function HubAPI.createVisualAdapter(...)
  if modules.nativevisuals then return modules.nativevisuals.create(...) end
  return nil
end
HubAPI.__contract = {
  provides = {
    "setup",
    "configure",
    "teardown",
    "areAbilitiesEnabled",
    "getAbilityAvailability",
    "getGameContext",
    "observeAbilityMode",
    "hasClashPrediction",
    "createCrateNetwork",
    "spinCrate",
    "resetState",
    "isNativeVisualAvailable",
    "applyVisualPolicy",
    "createVisualAdapter",
  },
  requires = {},
}

return HubAPI
