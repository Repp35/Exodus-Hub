--!optimize 2
-- @modules hubapi

local HubAPI = {}
local api = {}
local migrateUI
local boundary
function HubAPI.setup() return true end
function HubAPI.configure(loaded, scope)
  boundary = scope or loaded.gamescope.create(loaded, loaded.gamecontext.getProfile())
  api = loaded.gameruntime and loaded.gameruntime.createAPI(boundary.modules) or {}
  assert(type(api) == "table", "Game adapter must be a table")
  local functions = {
    getUIConfig = true,
    getAbilityAvailability = true,
    getChoices = true,
    getGameContext = true,
    observeAbilityMode = true,
    hasClashPrediction = true,
    resetState = true,
    observeState = true,
    getJumpButton = true,
    createActions = true,
    areAbilitiesEnabled = true,
    migrateConfig = true,
  }
  local tables = { controls = true, readouts = true, updateBlockers = true, miniVisibility = true }
  for name, value in pairs(api) do
    assert(functions[name] and type(value) == "function" or tables[name] and type(value) == "table", "Invalid game adapter field: " .. tostring(name))
  end
  local reserved = { onClose = true, onReload = true, onResetCharacter = true, onRejoin = true, onServerHop = true }
  for name, callback in pairs(api.controls or {}) do
    assert(type(name) == "string" and not reserved[name] and type(callback) == "function", "Invalid or reserved game control: " .. tostring(name))
  end
  boundary.validateKeys(api.miniVisibility or {})
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
function HubAPI.observeState(callback)
  if api.observeState then
    return api.observeState(callback)
  end
  return { Disconnect = function() end }
end
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
    },
  },
  provides = {
    "observeState",
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
  },
  requires = {},
}
return HubAPI
