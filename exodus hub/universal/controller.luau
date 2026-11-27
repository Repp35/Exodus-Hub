-- [[ controller ]]
--!optimize 2
-- @modules universalcontroller

local Controller = {}
local callbacks, signals = {}, {}
local dispatching = false
local function disconnectSignals()
  for _, connection in ipairs(signals) do
    connection:Disconnect()
  end
  table.clear(signals)
end
local function step(...)
  dispatching = true
  for _, entry in ipairs(callbacks) do
    if entry.alive and entry.scope.alive then
      local ok, reason = pcall(entry.callback, ...)
      if not ok then
        if entry.scope.fail then
          entry.scope.fail(reason)
        else
          warn("[Exodus Universal] " .. tostring(reason))
        end
      end
    end
  end
  dispatching = false
  for index = #callbacks, 1, -1 do
    if not callbacks[index].alive then
      table.remove(callbacks, index)
    end
  end
  if #callbacks == 0 then
    disconnectSignals()
  end
end
function Controller.setup() return true end
function Controller.teardown()
  disconnectSignals()
  table.clear(callbacks)
  return true
end
function Controller.connectPhysics(scope, callback)
  local entry = { alive = true, callback = callback, scope = scope }
  callbacks[#callbacks + 1] = entry
  scope.add(function()
    entry.alive = false
    if not dispatching then
      local index = table.find(callbacks, entry)
      if index then
        table.remove(callbacks, index)
      end
      if #callbacks == 0 then
        disconnectSignals()
      end
    end
  end)
  if #signals == 0 then
    local run = game:GetService("RunService")
    local before, after = run.PreSimulation or run.Stepped, run.PostSimulation or run.Heartbeat
    assert(before and after and before ~= after, "Two physics phases are required")
    signals[1] = before:Connect(function(first, second) step(second or first) end)
    signals[2] = after:Connect(step)
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
          activation.fail = fail
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
  provides = { "setup", "teardown", "create", "connectPhysics" },
  requires = {},
}
return Controller
