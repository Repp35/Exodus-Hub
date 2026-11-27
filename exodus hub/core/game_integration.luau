-- [[ game integration ]]
--!optimize 2
-- @modules gamecontext, hubapi, runtime

-- code
local __part_gamecontext = (function()
  local GameContext = {}
  local profile = { id = "universal", title = "Universal", author = "deltapolinha_2915" }
  function GameContext.setup() return true end
  function GameContext.configure(value)
    profile = table.clone(value)
    return true
  end
  function GameContext.getProfile() return table.clone(profile) end
  function GameContext.supportsModule() return true end
  GameContext.__contract = { provides = { "setup", "configure", "getProfile", "supportsModule" }, requires = {} }
  return GameContext
end)()
local __part_hubapi = (function()
  local HubAPI = {}
  local api = {}
  local migrateUI
  local boundary
  function HubAPI.setup() return true end
  function HubAPI.configure(loaded, scope)
    boundary = scope or loaded.gamescope.create(loaded, loaded.gamecontext.getProfile())
    api = loaded.gameruntime and loaded.gameruntime.createAPI(boundary.modules) or {}
    migrateUI = loaded.uiconfig and loaded.uiconfig.migrateConfig
    return true
  end
  function HubAPI.teardown()
    api, migrateUI, boundary = {}, nil, nil
    return true
  end
  function HubAPI.areAbilitiesEnabled() return api.areAbilitiesEnabled and api.areAbilitiesEnabled() or false end
  function HubAPI.getAbilityAvailability(name)
    if api.getAbilityAvailability then
      return api.getAbilityAvailability(name)
    end
    return false, "Recurso indisponível neste jogo"
  end
  function HubAPI.getChoices(name) return api.getChoices and api.getChoices(name) or {} end
  function HubAPI.getUIConfig() return boundary.definition(api.getUIConfig and api.getUIConfig() or {}, api.controls) end
  function HubAPI.getGameContext() return api.getGameContext and api.getGameContext() or {} end
  function HubAPI.observeAbilityMode(callback)
    if api.observeAbilityMode then
      return api.observeAbilityMode(callback)
    end
    return { Disconnect = function() end }
  end
  function HubAPI.hasClashPrediction() return api.hasClashPrediction and api.hasClashPrediction() or false end
  function HubAPI.resetState()
    if api.resetState then
      api.resetState()
    end
  end
  function HubAPI.isNativeVisualAvailable() return api.createVisualAdapter ~= nil end
  function HubAPI.applyVisualPolicy(...)
    if api.applyVisualPolicy then
      return api.applyVisualPolicy(...)
    end
    local _, target, watch = ...
    return target, watch
  end
  function HubAPI.createVisualAdapter(...) return api.createVisualAdapter and api.createVisualAdapter(...) end
  function HubAPI.getReadouts() return api.readouts or {} end
  function HubAPI.getJumpButton() return api.getJumpButton and api.getJumpButton() end
  function HubAPI.createActions(context)
    return boundary.actions(api.createActions and api.createActions(boundary.context(context, api.controls)) or {}, api.controls)
  end
  function HubAPI.getControls() return table.clone(api.controls or {}) end
  function HubAPI.canUpdate()
    for _, blocked in ipairs(api.updateBlockers or {}) do
      local ok, value = pcall(blocked)
      if not ok then
        return false, tostring(value)
      end
      if value then
        return false, "Aguardando um estado seguro do jogo"
      end
    end
    return true
  end
  function HubAPI.getMiniVisibility()
    local result = {}
    for key, rule in pairs(api.miniVisibility or {}) do
      local ok, visible = pcall(rule)
      if ok then
        result[key] = visible == true
      end
    end
    return result
  end
  function HubAPI.migrateConfig(data)
    local changed = migrateUI and migrateUI(data) or false
    if api.migrateConfig then
      return boundary.migrate(data, api.migrateConfig) or changed
    end
    return changed
  end
  HubAPI.__contract = {
    access = {
      default = "internal.read",
      methods = {
        configure = "infrastructure.write",
        resetState = "combat.runtime",
        createActions = "game.inventory",
        applyVisualPolicy = "render.write",
        createVisualAdapter = "render.write",
      },
    },
    provides = {
      "getReadouts",
      "getJumpButton",
      "createActions",
      "getControls",
      "canUpdate",
      "getMiniVisibility",
      "migrateConfig",
      "setup",
      "configure",
      "teardown",
      "areAbilitiesEnabled",
      "getAbilityAvailability",
      "getUIConfig",
      "getChoices",
      "getGameContext",
      "observeAbilityMode",
      "hasClashPrediction",
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
    if loaded.gameruntime then
      local boundary = loaded.gamescope.create(loaded, loaded.gamecontext.getProfile())
      return loaded.gameruntime.bind(boundary.modules, ...)
    end
    return {
      mode = loaded.gamecontext.getProfile().id,
    }
  end
  Runtime.__contract = { provides = { "setup", "bind" }, requires = {} }
  return Runtime
end)()

return { __bundle = { gamecontext = __part_gamecontext, hubapi = __part_hubapi, runtime = __part_runtime } }
