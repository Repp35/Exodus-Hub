-- [[ game_integration ]]

-- code
local __part_gamecontext = (function()
  local GameContext = {}; local profile = { id = "universal", title = "Universal", author = "deltapolinha_2915" }
  function GameContext.setup() return true end
  function GameContext.configure(value)
    profile = table.clone(value); return true
  end
  function GameContext.getProfile() return table.clone(profile) end
  function GameContext.isPhantomBall() return profile.id == "phantom-ball" end
  function GameContext.supportsModule() return true end
  GameContext.__contract = { provides = { "setup", "configure", "getProfile", "isPhantomBall", "supportsModule" }, requires = {} }; return GameContext
end)()
local __part_hubapi = (function()
  local HubAPI = {}; local modules = {}
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
  function HubAPI.getUIConfig() return modules.gameui and modules.gameui.definition or {} end
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
      "getUIConfig",
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
end)()
local __part_runtime = (function()
  local Runtime = {}
  function Runtime.setup() return true end
  function Runtime.bind(loaded, ...)
    if loaded.gameruntime then return loaded.gameruntime.bind(loaded, ...) end
    return {
      mode = loaded.gamecontext.getProfile().id,
      parryRemote = false,
      parryInitialized = false,
      watcher = false,
      ballSync = false,
      maintenance = false,
      ballSyncSubscribers = 0,
    }
  end
  Runtime.__contract = { provides = { "setup", "bind" }, requires = {} }; return Runtime
end)()

return { __bundle = { gamecontext = __part_gamecontext, hubapi = __part_hubapi, runtime = __part_runtime } }
