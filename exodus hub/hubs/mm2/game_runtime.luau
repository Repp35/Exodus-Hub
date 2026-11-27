-- [[ game runtime ]]
--!optimize 2

-- module
local Runtime = {}
local Bridge, current, loaded

-- setup
function Runtime.setup(deps)
  Bridge = deps.Bridge
  return true
end
function Runtime.reset()
  if not current then
    return
  end
  current.features.AutoFarm:StopMotion()
  current.features.MapTools:StopMovement()
  loaded.mm2native.reset()
end
function Runtime.teardown()
  if current then
    current.destroy()
  end
  current, loaded = nil, nil
end
function Runtime.bind(modules)
  Runtime.teardown()
  loaded = modules
  current = Bridge.create(modules)
  return { mode = "mm2" }
end

-- actions
function Runtime.createAPI(modules)
  local function feature(name) return current and current.features[name] end
  local function shoot()
    local object = feature("ShootMurder")
    return object and object:TryShoot(false) or false
  end
  local function throw()
    local object = feature("MurderCombat")
    return object and object:TryThrowManual(modules.utils.getConfigValue("MM2ManualThrowTargets"), modules.utils.getConfigValue("MM2ManualThrowFOV")) or false
  end
  local function tools(method, ...)
    local object = feature("MapTools")
    if not object then
      return false
    end
    return object[method](object, ...)
  end
  local function selectedPlayer() return game:GetService("Players"):FindFirstChild(modules.utils.getConfigValue("MM2TargetPlayer") or "None") end
  return {
    getUIConfig = function() return modules.gameui.definition end,
    resetState = Runtime.reset,
    createActions = function()
      return {
        callbacks = {
          mm2Shoot = shoot,
          mm2Throw = throw,
          mm2Map = function() return tools("TeleportToMap") end,
          mm2Lobby = function() return tools("TeleportToLobby") end,
          mm2Murderer = function() return tools("TeleportToRole", "Murderer") end,
          mm2Gun = function() return tools("TeleportToGun") end,
          mm2Holder = function() return tools("TeleportToRole", "GunHolder") end,
          mm2Player = function() return tools("TeleportToPlayer", selectedPlayer()) end,
          mm2Walk = function() return tools("WalkToPlayer", selectedPlayer()) end,
        },
        attach = function(definition, handle)
          local esp = feature("ESP")
          local categories = {
            MM2ESPMurderer = "Murderer",
            MM2ESPSheriff = "Sheriff",
            MM2ESPInnocent = "Innocent",
            MM2ESPCoins = "CandyCoin",
            MM2ESPGun = "Gun",
            MM2ESPSelf = "Self",
          }
          local category = categories[definition.key]
          if esp and category and handle.setColor then
            handle.setColor(esp.Colors[category])
          end
        end,
      }
    end,
    controls = { onMM2Shoot = shoot, onMM2Throw = throw },
    getChoices = function(name)
      if name == "mm2Players" then
        return tools("GetPlayerOptions") or {}
      end
      if name == "mm2Maps" then
        return tools("GetFavoriteMapOptions") or {}
      end
      return {}
    end,
    updateBlockers = {
      function()
        local farm, pickup, map = feature("AutoFarm"), feature("AutoGunPickup"), feature("MapTools")
        return farm and farm.Farming or pickup and pickup.Busy or map and map.IsWalking or modules.mm2native.busy()
      end,
    },
  }
end

-- contract
Runtime.__contract = {
  provides = { "setup", "reset", "teardown", "bind", "createAPI" },
  requires = { Bridge = "mm2bridge" },
  requiresMethods = { Bridge = { "create" } },
}
return Runtime
