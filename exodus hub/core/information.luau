-- [[ session information ]]
--!optimize 2
-- @modules information

local Information = {}
local utils, profile, autoexecute
local scope
local values = {}
local function available(value)
  if value == nil or tostring(value) == "" then
    return "Indisponível"
  end
  return tostring(value)
end
function Information.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  return true
end
function Information.setup(deps)
  Information.teardown()
  utils, profile, autoexecute = deps.Utils, deps.GameContext.getProfile(), deps.AutoExecute
  scope = deps.Lifetime.scope()
  local owner = scope
  local player = utils.getLocalPlayer()
  values = {
    username = player.Name,
    displayName = player.DisplayName,
    userId = player.UserId,
    game = profile.title,
    placeId = game.PlaceId,
    universeId = game.GameId,
    serverId = game.JobId,
    placeVersion = game.PlaceVersion,
    hubVersion = utils.version(),
    gameVersion = profile.version or "Sem integração",
    hubDevelopers = "deltapolinha_2915",
    gameDevelopers = table.concat(profile.developers or { profile.author or "Indisponível" }, ", "),
    creator = "Carregando…",
    group = "Carregando…",
    executor = "Indisponível",
    clientVersion = "Indisponível",
  }
  local environment = type(getgenv) == "function" and getgenv() or _G
  local identify = environment.identifyexecutor or environment.getexecutorname
  if type(identify) == "function" then
    local ok, name, build = pcall(identify)
    if ok then
      values.executor = available(name) .. (build and (" · " .. tostring(build)) or "")
    end
  end
  local ok, client = pcall(function() return version() end)
  if ok then
    values.clientVersion = client
  end
  task.spawn(function()
    local ok, info = pcall(function() return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId, Enum.InfoType.Asset) end)
    if not owner.alive then
      return
    end
    values.creator, values.group = "Indisponível", "Sem grupo"
    if ok and type(info) == "table" then
      values.game = info.Name or values.game
      local creator = info.Creator or {}
      values.creator = creator.Name or "Indisponível"
      if creator.CreatorType == "Group" or creator.CreatorType == Enum.CreatorType.Group then
        values.group = creator.Name or tostring(creator.CreatorTargetId or creator.Id)
        local groupOk, group = pcall(function() return game:GetService("GroupService"):GetGroupInfoAsync(creator.CreatorTargetId or creator.Id) end)
        if owner.alive and groupOk and type(group) == "table" and group.Owner then
          values.creator = group.Owner.Name
        end
      end
    end
  end)
  local elapsed, frames = 0, 0
  scope.connect(utils.getRunService().Heartbeat, function(dt)
    elapsed += dt
    frames += 1
    if elapsed < 0.5 then
      return
    end
    values.fps = string.format("%.0f FPS", frames / elapsed)
    elapsed, frames = 0, 0
    local ok, ping = pcall(function() return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
    values.ping = ok and type(ping) == "number" and string.format("%.0f ms", ping) or "Indisponível"
  end)
  return true
end
function Information.snapshot()
  local result = {}
  for key, value in pairs(values) do
    result[key] = available(value)
  end
  result.autoexecute = autoexecute.getStatus().mode
  local players, world = utils.getPlayers(), utils.getWorkspace()
  result.population = string.format("%d / %s", #players:GetPlayers(), tostring(players.MaxPlayers or "—"))
  result.country = available(world:GetAttribute("ServerCountry"))
  result.city = available(world:GetAttribute("ServerCity"))
  result.region = available(world:GetAttribute("ServerRegion"))
  result.uptime = string.format("%.0f min", math.max(0, os.clock() - utils.getLifecycle().startedAt) / 60)
  return result
end
Information.__contract = {
  access = { methods = { snapshot = "internal.read" } },
  provides = { "setup", "teardown", "snapshot" },
  requires = { Utils = "utils", GameContext = "gamecontext", Lifetime = "lifetime", AutoExecute = "autoexecute" },
  requiresMethods = {
    Utils = { "getLocalPlayer", "getRunService", "getPlayers", "getWorkspace", "getLifecycle", "version" },
    GameContext = { "getProfile" },
    Lifetime = { "scope" },
    AutoExecute = { "getStatus" },
  },
}
return Information
