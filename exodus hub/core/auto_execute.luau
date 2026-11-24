-- [[ executor startup and teleport execution ]]
--!optimize 2
-- @modules autoexecute

local AutoExecute = {}
local utils, observer, channel
local settings = { allGames = false, games = {} }
local environment, queue, startupDirectory
local syncing, armed = false, false
local mode = "Desativado"
local PATH = "Exodus Hub/auto_execute.json"
local SCRIPT = "Exodus Hub/auto_execute.luau"
local function gameKey() return game.GameId ~= 0 and game.GameId ~= nil and ("u:" .. tostring(game.GameId)) or ("p:" .. tostring(game.PlaceId)) end
local function anyEnabled() return settings.allGames or next(settings.games) ~= nil end
local function bootstrap()
  return [[local env = type(getgenv) == "function" and getgenv() or _G
if env.ExodusAutoExecuteStarted then return end
if game.PlaceId == 0 and not game:IsLoaded() then game.Loaded:Wait() end
local ok, state = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile("Exodus Hub/auto_execute.json")) end)
if not ok or type(state) ~= "table" then return end
if state.allGames ~= true and (type(state.games) ~= "table" or next(state.games) == nil) then return end
local key = game.GameId ~= 0 and game.GameId ~= nil and ("u:" .. tostring(game.GameId)) or ("p:" .. tostring(game.PlaceId))
local allowed = state.allGames == true or (type(state.games) == "table" and state.games[key] == true)
if not allowed then
  local queue = env.queue_on_teleport or env.queueonteleport or (env.syn and env.syn.queue_on_teleport) or (env.fluxus and env.fluxus.queue_on_teleport)
  if type(queue) == "function" then pcall(queue, readfile("Exodus Hub/auto_execute.luau")) end
  return
end
if type(state.entryURL) ~= "string" or not state.entryURL:match("^https://raw%.githubusercontent%.com/") then return end
env.ExodusAutoExecuteStarted = true
local attempt = 0
local function start()
  local valid, current = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile("Exodus Hub/auto_execute.json")) end)
  if not valid or type(current) ~= "table" or not (current.allGames == true or (type(current.games) == "table" and current.games[key] == true)) then
    env.ExodusAutoExecuteStarted = nil
    return
  end
  local success, reason = pcall(function()
    local owner, repo, _, path = state.entryURL:match("^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.+)$")
    local revision = current.revision
    local urls = {{url=state.entryURL}}
    if owner and type(revision)=="string" and #revision==40 and revision:match("^[%x]+$") then
      local prefix, suffix = owner .. "/" .. repo, owner .. "/" .. repo .. "@" .. revision .. "/" .. path
      for _, host in ipairs({"cdn.jsdelivr.net", "fastly.jsdelivr.net", "gcore.jsdelivr.net", "testingcf.jsdelivr.net", "quantil.jsdelivr.net"}) do
        urls[#urls+1]={url="https://" .. host .. "/gh/" .. suffix}
      end
      table.insert(urls,3,{url="https://rawcdn.githack.com/" .. prefix .. "/" .. revision .. "/" .. path})
      table.insert(urls,4,{url="https://raw.githack.com/" .. prefix .. "/" .. revision .. "/" .. path})
      urls[#urls+1]={url="https://github.com/" .. prefix .. "/raw/" .. revision .. "/" .. path}
      urls[#urls+1]={url="https://api.github.com/repos/" .. prefix .. "/contents/" .. path .. "?ref=" .. revision,headers={Accept="application/vnd.github.raw+json"}}
    end
    local fetchers, seen = {}, {}
    local function add(fn)
      if type(fn)=="function" and not seen[fn] then seen[fn]=true; fetchers[#fetchers+1]=fn end
    end
    add(env.request); add(env.http_request)
    for _, name in ipairs({"syn","fluxus","http"}) do if type(env[name])=="table" then add(env[name].request) end end
    add(function(options) return {StatusCode=200,Body=game:HttpGet(options.Url)} end)
    add(function(options) return {StatusCode=200,Body=game:HttpGetAsync(options.Url)} end)
    local chunk, failure
    for _, target in ipairs(urls) do
      for _, fetch in ipairs(fetchers) do
        local ok, response = pcall(fetch,{Url=target.url,Method="GET",Headers=target.headers,Timeout=1})
        if ok and type(response)=="table" then
          local status=tonumber(response.StatusCode or response.status_code) or 200
          local source=response.Body or response.body or response.ResponseBody
          if status>=200 and status<300 and type(source)=="string" then
            chunk, failure=loadstring(source)
            if chunk then env.ExodusCachedLoader={url=state.entryURL,source=source}; break end
          else
            failure="HTTP " .. tostring(status)
            if status==403 or status==429 then break end
          end
        else failure=tostring(response) end
      end
      if chunk then break end
    end
    if not chunk and type(env.ExodusCachedLoader)=="table" and env.ExodusCachedLoader.url==state.entryURL then
      chunk, failure=loadstring(env.ExodusCachedLoader.source)
    end
    assert(chunk,failure or "Todas as fontes do loader falharam")
    chunk()
  end)
  if success then return end
  attempt += 1
  local delay = math.min(60, 5 * 2 ^ math.min(attempt - 1, 4))
  if delay > 5 then
    warn("[Exodus Auto Execute] Erro: " .. tostring(reason) .. "; nova tentativa em " .. delay .. "s.")
    pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", {Title="Exodus · Erro", Text="Falha ao carregar. Nova tentativa em " .. delay .. "s.", Duration=5}) end)
  end
  task.delay(delay, start)
end
start()
]]
end
local function filesAvailable()
  return type(environment.readfile) == "function"
    and type(environment.writefile) == "function"
    and type(environment.isfile) == "function"
    and type(environment.isfolder) == "function"
    and type(environment.makefolder) == "function"
end
local function sync()
  if not channel then
    return
  end
  if not filesAvailable() then
    mode = "Executor sem persistência"
    return false
  end
  if not environment.isfolder("Exodus Hub") then
    environment.makefolder("Exodus Hub")
  end
  settings.entryURL = channel.entryURL()
  settings.revision = channel.revision
  environment.writefile(PATH, game:GetService("HttpService"):JSONEncode(settings))
  local source = bootstrap()
  environment.writefile(SCRIPT, source)
  if startupDirectory then
    if not environment.isfolder(startupDirectory) then
      environment.makefolder(startupDirectory)
    end
    if anyEnabled() then
      local installed = pcall(environment.writefile, startupDirectory .. "/ExodusHub.luau", source)
      if not installed then
        startupDirectory = nil
      end
    elseif type(environment.delfile) == "function" and environment.isfile(startupDirectory .. "/ExodusHub.luau") then
      pcall(environment.delfile, startupDirectory .. "/ExodusHub.luau")
    end
  end
  if anyEnabled() and queue and not armed then
    queue(source)
    armed = true
  end
  mode = not anyEnabled() and "Desativado"
    or (startupDirectory and "Ao entrar e após teleporte" or (queue and "Após teleporte; inicializador salvo" or "Inicializador salvo"))
  return true
end
function AutoExecute.setup(deps)
  AutoExecute.teardown()
  mode, syncing = "Desativado", false
  utils = deps.Utils
  environment = type(getgenv) == "function" and getgenv() or _G
  queue = environment.queue_on_teleport
    or environment.queueonteleport
    or (environment.syn and environment.syn.queue_on_teleport)
    or (environment.fluxus and environment.fluxus.queue_on_teleport)
  if type(queue) ~= "function" then
    queue = nil
  end
  startupDirectory = nil
  local directoryAPI = environment.getautoexecpath or environment.getautoexecfolder
  if type(directoryAPI) == "function" then
    local ok, path = pcall(directoryAPI)
    if ok and type(path) == "string" and path ~= "" then
      startupDirectory = path
    end
  elseif type(environment.delta) == "table" and type(environment.delta.AddTab) == "function" then
    startupDirectory = "DeltaPlugins"
  end
  settings = { allGames = false, games = {} }
  if filesAvailable() then
    local ok, saved = pcall(function()
      if environment.isfile(PATH) then
        return game:GetService("HttpService"):JSONDecode(environment.readfile(PATH))
      end
    end)
    if ok and type(saved) == "table" and type(saved.games) == "table" then
      settings.allGames = saved.allGames == true
      for key, value in pairs(saved.games) do
        if type(key) == "string" and value == true then
          settings.games[key] = true
        end
      end
    end
  end
  utils.setConfig({ AutoExecuteOnJoin = settings.allGames or settings.games[gameKey()] == true, AutoExecuteAllGames = settings.allGames })
  observer = utils.observeConfig(function(changes)
    if syncing or (changes.AutoExecuteOnJoin == nil and changes.AutoExecuteAllGames == nil) then
      return
    end
    local previous = { allGames = settings.allGames, games = table.clone(settings.games), entryURL = settings.entryURL }
    if utils.getConfigValue("AutoExecuteOnJoin") ~= true then
      if settings.allGames then
        settings.games = {}
      end
      settings.allGames = false
      settings.games[gameKey()] = nil
    elseif changes.AutoExecuteAllGames ~= nil then
      settings.allGames = changes.AutoExecuteAllGames == true
      if not settings.allGames then
        settings.games = { [gameKey()] = true }
      end
    else
      settings.games[gameKey()] = true
      settings.allGames = utils.getConfigValue("AutoExecuteAllGames") == true
    end
    local ok, result = pcall(sync)
    if not ok or result == false then
      utils.recordError("AutoExecute", ok and mode or result)
      settings = previous
      if filesAvailable() then
        pcall(function() environment.writefile(PATH, game:GetService("HttpService"):JSONEncode(previous)) end)
      end
    end
    syncing = true
    utils.setConfig({ AutoExecuteOnJoin = settings.allGames or settings.games[gameKey()] == true, AutoExecuteAllGames = settings.allGames })
    syncing = false
  end)
  return true
end
function AutoExecute.start(transport)
  channel = transport
  if anyEnabled() then
    local ok, reason = pcall(sync)
    if not ok then
      utils.recordError("AutoExecute", reason)
    end
  end
  return true
end
function AutoExecute.getStatus() return { mode = mode, startup = startupDirectory ~= nil, teleport = queue ~= nil } end
function AutoExecute.teardown()
  if observer then
    observer:Disconnect()
    observer = nil
  end
  utils, channel, armed = nil, nil, false
  return true
end
AutoExecute.__config =
  { schema = { AutoExecuteOnJoin = "boolean", AutoExecuteAllGames = "boolean" }, defaults = { AutoExecuteOnJoin = false, AutoExecuteAllGames = false } }
AutoExecute.__contract = {
  access = { methods = { getStatus = "internal.read" } },
  provides = { "setup", "start", "teardown", "getStatus" },
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "setConfig", "getConfigValue", "observeConfig", "recordError" } },
}
return AutoExecute
