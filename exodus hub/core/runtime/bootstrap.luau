-- [[ bootstrap ]]
--!optimize 2
-- @modules bootstrap

local Bootstrap = {}
function Bootstrap.setup() return true end
function Bootstrap.start(loaded, order, urls, profile, transport)
  loaded.gamecontext.configure(profile)
  local utils = loaded.utils
  local miniScale = {
    read = function() return utils.getConfigValue("MiniUIScale") end,
    observe = function(callback)
      return utils.observeConfig(function(changes)
        if changes.MiniUIScale ~= nil then
          callback()
        end
      end)
    end,
  }
  local boundary = loaded.gamescope.create(loaded, profile, { miniScale = miniScale })
  boundary.validateDefaults(profile.defaults)
  loaded.hubapi.configure(loaded, boundary)
  utils.configure(loaded.permissions.resolve("utils", loaded))
  utils.start()
  if type(_G.Exodus) == "table" then
    _G.Exodus.Utils = utils
  end
  loaded.status.configure(loaded, utils.recordError)
  utils.setLifecyclePhase("configuring")
  local installers, pages, sections = {}, {}, {}
  for _, name in ipairs(order) do
    if loaded[name].__contract.section then
      sections[#sections + 1] = { order = loaded[name].__contract.section, name = name, definition = loaded[name].definition }
    end
    if loaded[name].__contract.page then
      pages[#pages + 1] = { order = loaded[name].__contract.page, name = name, definition = loaded[name].definition }
    end
    if loaded[name].__contract.component == true then
      local path = assert(loaded.permissions.getPath(name))
      assert(path:sub(1, 14) == "ui/components/", "Component implementations belong to the UI library")
      assert(type(loaded[name].install) == "function", "Component installer missing: " .. name)
      installers[#installers + 1] = { install = loaded[name].install }
    end
  end
  loaded.uikit.configure(installers)
  table.sort(pages, function(a, b) return a.order < b.order or a.order == b.order and a.name < b.name end)
  local definitions = {}
  for _, page in ipairs(pages) do
    definitions[#definitions + 1] = page.definition
  end
  table.sort(sections, function(a, b) return a.order < b.order or a.order == b.order and a.name < b.name end)
  local universal = {}
  for _, section in ipairs(sections) do
    universal[#universal + 1] = section.definition
  end
  loaded.uiconfig.configure(definitions, universal)
  loaded.config.reset()
  for name, module in pairs(loaded) do
    if module.__config then
      local accepted, reason = loaded.config.register(name, module.__config, boundary.configScope(name))
      assert(accepted, "Invalid configuration schema: " .. name .. " (" .. tostring(reason or "invalid fields, keys or defaults") .. ")")
    end
  end
  utils.setConfigModule(loaded.config)
  utils.setConfig(loaded.config.defaults({ player = utils.getLocalPlayer(), profile = boundary.profile }))
  utils.loadConfig()
  utils.setModuleURLs(urls)
  local binds = {}
  for _, name in ipairs(order) do
    local module = loaded[name]
    if module.__contract.bindCharacter then
      assert(type(module.bindCharacter) == "function" and type(module.detachCharacter) == "function", "Incomplete character contract: " .. name)
      binds[#binds + 1] = { name = name, bind = module.bindCharacter, detach = module.detachCharacter }
    end
  end
  utils.setLifecyclePhase("initializing")
  for _, name in ipairs(order) do
    local module = loaded[name]
    if name ~= "utils" and name ~= "config" and name ~= "uiconfig" then
      local deps = loaded.permissions.resolve(name, loaded)
      deps = boundary.dependencies(name, deps)
      if name == "character" then
        deps.characterBinds = binds
      end
      if type(module.teardown) == "function" then
        local cleanup = { Connected = true }
        function cleanup:Disconnect()
          if not self.Connected then
            return
          end
          self.Connected = false
          module.teardown()
        end
        utils.trackGlobal(cleanup)
      end
      local ok, reason = module.setup(deps)
      assert(ok == true, name .. ".setup: " .. tostring(reason))
    end
  end
  utils.setDiagnosticsModules(loaded)
  local runtime, reason = loaded.runtime.bind(loaded, order, game:GetService("HttpService"), transport.report)
  assert(type(runtime) == "table", tostring(reason))
  local controls = loaded.hubapi.getControls()
  controls.onClose = function()
    _G.ExodusLoaderRecoveryToken = nil
    _G.ExodusShutdownReason = "close"
    return utils.stop()
  end
  controls.onReload = transport.reload
  controls.onResetCharacter = function()
    local player = utils.getLocalPlayer()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
      return false, "Personagem indisponível"
    end
    humanoid.Health = 0
    return true
  end

  for action, method in pairs({ onRejoin = "rejoin", onServerHop = "hop" }) do
    controls[action] = function()
      local function report(message) loaded.ui.notify(message, "server_navigation", "info", 5) end
      local ok, err = loaded.servers[method](report)
      if ok == false then
        utils.recordError("Servers", err)
        report(err)
      end
    end
  end
  local view
  local cleanup = { Connected = true }
  function cleanup:Disconnect()
    if not self.Connected then
      return
    end
    self.Connected = false
    if view then
      view.fade()
    end
    loaded.ui.teardown()
  end
  utils.trackGlobal(cleanup)
  local definition = loaded.hubapi.getUIConfig()
  local pages = loaded.uiconfig.getPages(definition)
  definition.pages = pages
  view = loaded.ui.create({
    name = utils.name(),
    author = utils.author(),
    version = utils.version(),
    state = utils,
    miniScale = miniScale,
    effectsEnabled = function() return utils.getConfigValue("AntiLagEnabled") ~= true end,
    headerButtons = { { id = "information", page = "information", icon = "information" }, { id = "config", page = "config", icon = "settings" } },
    controls = controls,
    definition = definition,
    beforePresent = transport.present,
    information = loaded.information,
    capabilities = { clashPrediction = loaded.hubapi.hasClashPrediction() },
    model = {
      getAvailability = loaded.hubapi.getAbilityAvailability,
      getChoices = loaded.hubapi.getChoices,
      getReadouts = loaded.hubapi.getReadouts,
      getVisibility = loaded.hubapi.getMiniVisibility,
      conditionsEnabled = loaded.hubapi.areAbilitiesEnabled,
      observeState = loaded.hubapi.observeState,
    },
    actionsFactory = function(context) return loaded.uiactions.create(context) end,
  })
  if type(_G.Exodus) == "table" then
    local options = {}
    for _, method in ipairs({ "get", "isEnabled", "describe", "observe" }) do
      options[method] = loaded.options[method]
    end
    _G.Exodus.Options = table.freeze(options)
  end
  loaded.updates.start(transport)
  loaded.autoexecute.start(transport)
  return true, runtime
end
Bootstrap.__contract = { provides = { "setup", "start" }, requires = {} }
return Bootstrap
