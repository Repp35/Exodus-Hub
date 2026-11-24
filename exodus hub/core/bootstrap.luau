-- [[ session bootstrap ]]
--!optimize 2
-- @modules bootstrap

local Bootstrap = {}
function Bootstrap.setup() return true end
function Bootstrap.start(loaded, order, urls, profile, transport)
  loaded.gamecontext.configure(profile)
  loaded.hubapi.configure(loaded)
  local utils = loaded.utils
  utils.configure(loaded.permissions.resolve("utils", loaded))
  utils.start()
  if type(_G.Exodus) == "table" then
    _G.Exodus.Utils = utils
  end
  loaded.status.configure(loaded, utils.recordError)
  utils.setLifecyclePhase("configuring")
  for name, module in pairs(loaded) do
    if module.__config then
      assert(loaded.config.register(name, module.__config), "Invalid configuration schema: " .. name)
    end
  end
  utils.setConfigModule(loaded.config)
  utils.setConfig(loaded.config.defaults())
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
      if name == "character" then
        deps.characterBinds = binds
      end
      -- Register before setup so partial initialization is also cleaned up.
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
  controls.onClose = utils.stop
  controls.onReload = transport.reload
  controls.onUniversalToggle = function(feature, enabled)
    local module = loaded[string.lower(feature)]
    if module and module.setEnabled then
      local ok, err = module.setEnabled(enabled)
      if ok == false then
        utils.recordError(feature, err)
      end
    end
  end
  controls.onUniversalValue = function(feature, value)
    local module = loaded[string.lower(feature)]
    if module and module.setValue then
      local ok, err = module.setValue(value)
      if ok == false then
        utils.recordError(feature, err)
      end
    end
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
  local dependencies = loaded.permissions.resolve("ui", loaded)
  dependencies.Controls = controls
  local ok, err = loaded.ui.setup(dependencies)
  assert(ok == true, tostring(err))
  loaded.updates.start(transport)
  return true, runtime
end
Bootstrap.__contract = { provides = { "setup", "start" }, requires = {} }
return Bootstrap
