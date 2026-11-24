-- [[ server navigation ]]
--!optimize 2
-- @modules servers

local Servers = {}

local utils
local failureConnection
local generation = 0
local busy = false
local busyUntil = 0
local reporter = nil
local pendingServerId

-- configuration
local CONFIG = {
  MAX_PING_MS = 100,
  MAX_PAGES = 3,
  PAGE_SIZE = 100,
  PAGE_DELAY = 0.5,
  TELEPORT_TIMEOUT = 15,
}

-- helpers
local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local function begin(callback)
  if not utils or not utils.isActive() then
    return nil, "Hub inativo"
  end
  if busy and os.clock() < busyUntil then
    return nil, "Já existe uma busca ou um teleporte em andamento"
  end
  generation = generation + 1
  busy, busyUntil, reporter, pendingServerId = true, os.clock() + 60, callback, nil
  return generation
end
local function report(message)
  if type(reporter) == "function" then
    local ok, reason = pcall(reporter, message)
    if not ok and utils then
      utils.recordError("Servers.callback", reason)
    end
  end
end
local function teleport(serverId, token)
  if token ~= generation or not utils or not utils.isActive() then
    return false, "Operação cancelada"
  end
  local player = utils.getLocalPlayer()
  if not player then
    busy = false
    return false, "Jogador indisponível"
  end
  busyUntil, pendingServerId = os.clock() + CONFIG.TELEPORT_TIMEOUT, serverId
  local ok, err = pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, serverId, player) end)
  if token ~= generation or not utils then
    return false, "Operação cancelada"
  end
  if not ok then
    busy, pendingServerId = false, nil
    return false, tostring(err)
  end
  task.delay(CONFIG.TELEPORT_TIMEOUT, function()
    if token ~= generation or not busy or not utils then
      return
    end
    busy, pendingServerId = false, nil
    report("O teleporte não foi concluído; você pode tentar novamente")
  end)
  return true
end

-- actions
function Servers.rejoin(callback)
  local token, err = begin(callback)
  if not token then
    return false, err
  end
  if type(game.JobId) ~= "string" or game.JobId == "" then
    busy = false
    return false, "Servidor atual indisponível"
  end
  report("Reconectando ao servidor atual...")
  return teleport(game.JobId, token)
end
function Servers.hop(callback)
  local token, err = begin(callback)
  if not token then
    return false, err
  end
  local http = game:GetService("HttpService")
  local best, cursor
  local seenCursors = {}
  report("Buscando servidores com ping informado de até " .. CONFIG.MAX_PING_MS .. " ms...")
  for page = 1, CONFIG.MAX_PAGES do
    if token ~= generation or not utils or not utils.isActive() then
      return false, "Operação cancelada"
    end
    local url = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=%d&excludeFullGames=true"):format(
      tostring(game.PlaceId),
      CONFIG.PAGE_SIZE
    )
    if cursor then
      url = url .. "&cursor=" .. http:UrlEncode(cursor)
    end
    local ok, result = pcall(function() return http:JSONDecode(game:HttpGet(url)) end)
    if token ~= generation or not utils or not utils.isActive() then
      return false, "Operação cancelada"
    end
    if not ok or type(result) ~= "table" or type(result.data) ~= "table" then
      busy = false
      return false, "Falha ao consultar servidores: " .. tostring(result)
    end
    for _, server in ipairs(result.data) do
      if
        type(server) == "table"
        and type(server.id) == "string"
        and server.id ~= ""
        and server.id ~= game.JobId
        and finite(server.playing)
        and finite(server.maxPlayers)
        and server.playing >= 0
        and server.maxPlayers > 0
        and server.playing < server.maxPlayers
        and finite(server.ping)
        and server.ping > 0
        and server.ping <= CONFIG.MAX_PING_MS
      then
        if not best or server.ping < best.ping or (server.ping == best.ping and server.playing < best.playing) then
          best = server
        end
      end
    end
    cursor = result.nextPageCursor
    if type(cursor) ~= "string" or cursor == "" or seenCursors[cursor] then
      break
    end
    seenCursors[cursor] = true
    if page < CONFIG.MAX_PAGES then
      task.wait(CONFIG.PAGE_DELAY)
    end
  end
  if token ~= generation or not utils or not utils.isActive() then
    return false, "Operação cancelada"
  end
  if not best then
    busy = false
    return false, "Nenhum outro servidor com vaga e ping informado de até " .. CONFIG.MAX_PING_MS .. " ms foi encontrado"
  end
  report(("Entrando no servidor com menor ping informado: %.0f ms..."):format(best.ping))
  return teleport(best.id, token)
end

-- lifecycle
function Servers.teardown()
  generation = generation + 1
  busy, reporter, pendingServerId = false, nil, nil
  if failureConnection then
    if utils then
      utils.untrackGlobal(failureConnection)
    end
    failureConnection:Disconnect()
    failureConnection = nil
  end
  utils = nil
  return true
end
function Servers.setup(deps)
  Servers.teardown()
  if type(deps) ~= "table" or type(deps.Utils) ~= "table" then
    return false, "Utils ausente"
  end
  utils = deps.Utils
  failureConnection = game:GetService("TeleportService").TeleportInitFailed:Connect(function(player, _, message, placeId, options)
    if not utils or player ~= utils.getLocalPlayer() or placeId ~= game.PlaceId or not busy or not pendingServerId then
      return
    end
    if options and options.ServerInstanceId ~= "" and options.ServerInstanceId ~= pendingServerId then
      return
    end
    busy, pendingServerId = false, nil
    report("Teleporte falhou: " .. tostring(message))
    utils.recordError("Servers", message)
  end)
  utils.trackGlobal(failureConnection)
  return true
end

-- contract
Servers.__contract = {
  access = { default = "tooling.execute" },
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "getLocalPlayer", "isActive", "trackGlobal", "untrackGlobal", "recordError" } },
  provides = { "setup", "teardown", "rejoin", "hop" },
}

return Servers
