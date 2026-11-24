-- [[ Phantom Ball inventory actions ]]
--!optimize 2
local Actions = {}
function Actions.setup() return true end
function Actions.create(loaded, context)
  local scope, info, Utils = context.scope, loaded.gameinfo, loaded.utils
  local callbacks, states, handles = {}, {}, {}
  local spinActive, spinGeneration = nil, 0
  local CONFIG = { SPIN_INTERVAL = 0.3 }
  local modes = { spinSword = "SwordCrate", spinEmote = "EmoteCrate", spinExplosion = "FinisherCrate" }
  local function paintSpin()
    for action, crate in pairs(modes) do
      if handles[action] then
        handles[action].setValue(spinActive == crate)
      end
    end
  end
  for action, crate in pairs(modes) do
    states[action] = function() return spinActive == crate end
    callbacks[action] = function(enabled)
      spinGeneration += 1
      if enabled then
        spinActive = crate
      elseif spinActive == crate then
        spinActive = nil
      end
      paintSpin()
      if not enabled then
        return true
      end
      local generation = spinGeneration
      task.spawn(function()
        local network = info.createCrateNetwork()
        while scope.alive and generation == spinGeneration and spinActive == crate and Utils.isActive() do
          local sent = info.spinCrate(network, crate, function() return scope.alive and generation == spinGeneration and spinActive == crate end)
          if not sent then
            break
          end
          task.wait(CONFIG.SPIN_INTERVAL)
        end
        if scope.alive and generation == spinGeneration then
          spinActive = nil
          paintSpin()
        end
      end)
      return true
    end
  end

  scope.add(function()
    spinGeneration += 1
  end)
  return {
    callbacks = callbacks,
    states = states,
    attach = function(definition, handle)
      if definition.action then
        handles[definition.action] = handle
      end
    end,
  }
end
Actions.__contract = { provides = { "setup", "create" }, requires = {} }
return Actions
