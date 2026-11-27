-- [[ game runtime ]]
--!optimize 2

local Runtime = {}
local loaded, scope, character
function Runtime.setup() return true end
function Runtime.reset()
  if not loaded then
    return
  end
  loaded.mm2movement.cancel()
  loaded.mm2farm.reset()
  loaded.mm2pickup.reset()
  loaded.mm2weapons.reset()
  loaded.mm2maptools.reset()
  loaded.mm2alerts.reset()
end
function Runtime.teardown()
  Runtime.reset()
  if scope then
    scope.destroy()
  end
  scope, loaded, character = nil, nil, nil
end
function Runtime.bind(modules)
  Runtime.teardown()
  loaded, scope = modules, modules.lifetime.scope()
  local owner = scope
  modules.mm2state.bind(scope)
  modules.mm2world.bind(scope)
  modules.mm2movement.bind(scope)
  modules.mm2visuals.bind(scope)
  modules.mm2alerts.bind(modules.ui.notifyCorner)
  local elapsed, slow, errors = 0, 0, {}
  local function run(name, callback, ...)
    local ok, reason = pcall(callback, ...)
    if not ok then
      modules.mm2movement.cancel()
      if os.clock() >= (errors[name] or 0) then
        errors[name] = os.clock() + 5
        modules.utils.recordError("mm2." .. name, tostring(reason))
      end
    end
  end
  scope.connect(game:GetService("RunService").Heartbeat, function(dt)
    elapsed += dt
    slow += dt
    if elapsed < 0.1 then
      return
    end
    elapsed = 0
    if not modules.utils.isActive() then
      Runtime.reset()
      modules.mm2visuals.step()
      return
    end
    local snap = modules.mm2state.live(modules.utils.getLocalPlayer(), true)
    local nextCharacter = snap and snap.character
    if nextCharacter ~= character then
      Runtime.reset()
      character = nextCharacter
    end
    run("world", modules.mm2world.refresh)
    run("movement", modules.mm2movement.step)
    run("weapons", modules.mm2weapons.step)
    local collecting = false
    run("pickup", function() collecting = modules.mm2pickup.step(snap) end)
    if not collecting then
      run("farm", modules.mm2farm.step, snap)
    end
    run("map", modules.mm2maptools.step)
    if slow >= 0.25 then
      slow = 0
      run("visuals", modules.mm2visuals.step)
      run("alerts", modules.mm2alerts.step)
    end
  end)
  scope.add(modules.utils.observeConfig(function(changes)
    if changes.MM2AutoFarm == false then
      modules.mm2farm.reset()
    end
    if changes.MM2ESP == false then
      modules.mm2visuals.step()
    end
  end))
  owner.add(function()
    modules.mm2movement.teardown()
    modules.mm2world.teardown()
    modules.mm2state.teardown()
    modules.mm2visuals.teardown()
  end)
  return { mode = "mm2" }
end
function Runtime.createAPI(modules)
  return {
    getUIConfig = function() return modules.gameui.definition end,
    resetState = Runtime.reset,
    createActions = function(context)
      local function checked(action)
        return function()
          modules.mm2movement.cancel()
          local ok, reason = action()
          if ok == false and reason then
            context.notify(reason, true)
          end
          return ok
        end
      end
      return {
        callbacks = {
          mm2Shoot = function() return modules.mm2weapons.shoot(false) end,
          mm2Map = checked(modules.mm2maptools.map),
          mm2Lobby = checked(modules.mm2maptools.lobby),
          mm2Murderer = checked(function() return modules.mm2maptools.role("Murderer") end),
          mm2Gun = checked(modules.mm2maptools.gun),
          mm2Holder = checked(modules.mm2maptools.holder),
          mm2Player = checked(function() return modules.mm2maptools.player(false) end),
          mm2Walk = checked(function() return modules.mm2maptools.player(true) end),
        },
      }
    end,
    controls = { onMM2Shoot = function() return modules.mm2weapons.shoot(false) end },
    getChoices = function(name)
      if name == "mm2Players" then
        return modules.mm2maptools.players()
      end
      if name == "mm2Maps" then
        return modules.mm2maptools.maps()
      end
      return {}
    end,
    updateBlockers = { modules.mm2movement.busy },
  }
end
Runtime.__contract = { provides = { "setup", "reset", "teardown", "bind", "createAPI" }, requires = {} }
return Runtime
