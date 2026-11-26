-- [[ information ]]
--!optimize 2
-- @modules information

local Information = {}
local utils, profile, location, scope
local values, errors = {}, {}
local function text(value)
  if value == nil then
    return nil
  end
  local content = tostring(value)
  return content:match("%S") and content or nil
end
local function escape(value) return (tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")) end
local function finite(value) return type(value) == "number" and value == value and value >= 0 and value < math.huge end
function Information.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  return true
end
function Information.setup(deps)
  Information.teardown()
  utils, profile, location = deps.Utils, deps.GameContext.getProfile(), deps.Location
  scope = deps.Lifetime.scope()
  local owner, player = scope, utils.getLocalPlayer()
  values, errors = { username = player.Name, hubVersion = utils.version(), gameVersion = profile.version }, {}
  local developers, seen = {}, {}
  local function developer(name)
    name = text(name)
    if name and not seen[string.lower(name)] then
      seen[string.lower(name)] = true
      developers[#developers + 1] = name
    end
  end
  developer(utils.author())
  for _, name in ipairs(profile.developers or {}) do
    developer(name)
  end
  values.developers = developers
  local environment = type(getgenv) == "function" and getgenv() or _G
  local identify = environment.identifyexecutor or environment.getexecutorname
  if type(identify) == "function" then
    local ok, name, build = pcall(identify)
    if ok and text(name) then
      values.executor = name .. (text(build) and (" " .. tostring(build)) or "")
    end
  end
  if not values.executor then
    errors.executor = "Executor: identificação bloqueada."
  end
  local ok, client = pcall(function() return version() end)
  if ok then
    values.clientVersion = text(client)
  end
  if not values.clientVersion then
    errors.clientVersion = "Roblox: não foi possível obter a versão."
  end
  task.spawn(function()
    if not owner.alive then
      return
    end
    local ok, info = pcall(function()
      local marketplace = game:GetService("MarketplaceService")
      return marketplace:GetProductInfoAsync(game.PlaceId, Enum.InfoType.Asset)
    end)
    if not ok then
      ok, info = pcall(function() return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId, Enum.InfoType.Asset) end)
    end
    if not owner.alive then
      return
    end
    if not ok or type(info) ~= "table" then
      ok, info = pcall(function()
        local body = game:HttpGet("https://games.roblox.com/v1/games?universeIds=" .. tostring(game.GameId))
        local data = game:GetService("HttpService"):JSONDecode(body).data[1]
        assert(type(data) == "table", "Game metadata missing")
        return { Name = data.name, Creator = { Name = data.creator.name, CreatorType = data.creator.type, CreatorTargetId = data.creator.id } }
      end)
      if not owner.alive then
        return
      end
    end
    local creator = ok and type(info) == "table" and info.Creator or {}
    local id = creator.CreatorTargetId or creator.Id or game.CreatorId
    if ok and type(info) == "table" then
      values.game, values.creator = text(info.Name), text(creator.Name)
    end
    local groupOwned = creator.CreatorType == "Group" or creator.CreatorType == Enum.CreatorType.Group or game.CreatorType == Enum.CreatorType.Group
    if groupOwned then
      values.group = values.creator
      local groupOk, group = pcall(function() return game:GetService("GroupService"):GetGroupInfoAsync(id) end)
      if not owner.alive then
        return
      end
      if groupOk and type(group) == "table" then
        values.group = text(group.Name) or values.group
        values.creator = group.Owner and text(group.Owner.Name) or nil
      else
        values.creator = nil
        errors.creator = "Criador: falha ao consultar o grupo."
      end
    elseif not values.creator and id and id > 0 then
      local found, name = pcall(function() return utils.getPlayers():GetNameFromUserIdAsync(id) end)
      if not owner.alive then
        return
      end
      if found then
        values.creator = text(name)
      end
    end
    if values.game and values.creator then
      errors.game = nil
    else
      errors.game = "Jogo: não foi possível obter todos os dados."
    end
  end)
  task.delay(8, function()
    if owner.alive and (not values.game or not values.creator) then
      errors.game = "Jogo: a consulta não respondeu."
    end
  end)
  local elapsed, frames = 0, 0
  local run = utils.getRunService()
  scope.connect(run.RenderStepped or run.Heartbeat, function(dt)
    elapsed += dt
    frames += 1
    if elapsed < 0.5 then
      return
    end
    values.fps = string.format("%.0f", frames / elapsed)
    elapsed, frames = 0, 0
    local pingOk, ping = pcall(function() return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
    if not pingOk or not finite(ping) then
      pingOk, ping = pcall(function() return player:GetNetworkPing() * 1000 end)
    end
    if pingOk and finite(ping) then
      values.ping, errors.ping = string.format("%.0f ms", ping), nil
    else
      values.ping, errors.ping = nil, "Ping: não foi possível medir."
    end
  end)
  return true
end
function Information.snapshot()
  local result, issues = {}, table.clone(errors)
  local server, locationError = location.snapshot()
  if locationError then
    issues.location = locationError
  end
  local function section(key, fields, failures)
    local lines = {}
    for _, field in ipairs(fields) do
      if text(field[2]) then
        lines[#lines + 1] = "<b>" .. escape(field[1]) .. ":</b> " .. escape(field[2])
      end
    end
    for _, failure in ipairs(failures or {}) do
      if issues[failure] then
        lines[#lines + 1] = "<i>" .. escape(issues[failure]) .. "</i>"
      end
    end
    if #lines > 0 then
      result[key] = table.concat(lines, "\n")
    end
  end
  section(
    "session",
    { { "Usuário", values.username }, { "Executor", values.executor }, { "FPS", values.fps }, { "Ping", values.ping } },
    { "executor", "ping" }
  )
  section("game", { { "Nome", values.game }, { "Criador", values.creator }, { "Grupo", values.group } }, { "game", "creator" })
  local players = utils.getPlayers()
  section("server", {
    { "País", server.country and (server.country .. (server.estimated and " (estimativa)" or "")) or "Consultando…" },
    { "Cidade", server.city or "Não confirmada" },
    { "Fonte", server.source },
    { "Jogadores", tostring(#players:GetPlayers()) .. (finite(players.MaxPlayers) and (" / " .. tostring(players.MaxPlayers)) or "") },
  }, { "location" })
  section("versions", { { "Hub", values.hubVersion }, { "Script do jogo", values.gameVersion }, { "Roblox", values.clientVersion } }, { "clientVersion" })
  if #values.developers > 0 then
    local names = {}
    for _, name in ipairs(values.developers) do
      names[#names + 1] = "• <b>" .. escape(name) .. "</b>"
    end
    result.developers = table.concat(names, "\n")
  end
  return result, issues
end
Information.__contract = {
  access = { methods = { snapshot = "internal.read" } },
  provides = { "setup", "teardown", "snapshot" },
  requires = { Utils = "utils", GameContext = "gamecontext", Lifetime = "lifetime", Location = "serverlocation" },
  requiresMethods = {
    Utils = { "getLocalPlayer", "getRunService", "getPlayers", "version", "author" },
    GameContext = { "getProfile" },
    Lifetime = { "scope" },
    Location = { "snapshot" },
  },
}
return Information
