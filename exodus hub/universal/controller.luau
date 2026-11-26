-- [[ controller ]]
--!optimize 2
-- @modules universalcontroller

local Controller = {}
function Controller.setup() return true end
function Controller.connectPhysics(scope, callback, before)
  local run = game:GetService("RunService")
  before = before or run.PreSimulation or run.Stepped
  local after = run.Heartbeat or run.PostSimulation
  assert(before or after, "sinal de física indisponível")
  if before then
    scope.connect(before, callback)
  end
  if after and after ~= before then
    scope.connect(after, callback)
  end
end
function Controller.create(utils, lifetime, definition)
  local root = lifetime.scope()
  local active, activation, applying = false, nil, false
  local controller = {}
  local function stop()
    active = false
    if activation then
      activation.destroy()
      activation = nil
    end
    if definition.stop then
      definition.stop()
    end
  end
  local function fail(reason)
    applying = true
    pcall(stop)
    utils.setConfig({ [definition.key] = false })
    utils.recordError(definition.key, tostring(reason))
    applying = false
    return false, tostring(reason)
  end
  function controller.sync()
    if applying or not root.alive then
      return true
    end
    applying = true
    local ok, reason = pcall(function()
      local enabled = definition.isEnabled and definition.isEnabled() or utils.getConfigValue(definition.key) == true
      if enabled ~= active then
        if enabled then
          activation = root.child()
          active = true
          local connect = activation.connect
          activation.connect = function(signal, callback)
            return connect(signal, function(...)
              local ok, reason = pcall(callback, ...)
              if not ok then
                fail(reason)
              end
            end)
          end
          assert(definition.start(activation) ~= false, "falha ao iniciar recurso")
        else
          stop()
        end
      end
      if active and definition.update then
        definition.update()
      end
    end)
    if not ok then
      return fail(reason)
    end
    applying = false
    return true
  end
  function controller.setEnabled(enabled)
    if not root.alive then
      return false, "recurso encerrado"
    end
    if not utils.setConfig({ [definition.key] = enabled == true }) then
      return false, "configuração rejeitada"
    end
    local ok, reason = controller.sync()
    if ok and enabled == true and not active then
      return false, "falha ao ativar recurso"
    end
    return ok, reason
  end
  function controller.setValue(value)
    value = tonumber(value)
    if not value or value ~= value or math.abs(value) == math.huge or not definition.valueKey then
      return false, "valor inválido"
    end
    value = math.clamp(value, definition.min or 0, definition.max or 200)
    if not utils.setConfig({ [definition.valueKey] = value }) then
      return false, "configuração rejeitada"
    end
    return controller.sync()
  end
  root.add(utils.observeConfig(function(changes)
    if changes[definition.key] ~= nil or definition.valueKey and changes[definition.valueKey] ~= nil then
      controller.sync()
    end
  end))
  local cleanup = { Disconnect = function() root.destroy() end }
  utils.trackGlobal(cleanup)
  root.add(function() utils.untrackGlobal(cleanup) end)
  root.add(stop)
  function controller.destroy() root.destroy() end
  return controller
end
Controller.__contract = {
  access = { default = "lifetime.manage" },
  provides = { "setup", "create", "connectPhysics" },
  requires = {},
}
return Controller
