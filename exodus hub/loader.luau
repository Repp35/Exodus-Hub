-- [[ loader ]]

-- configuration
local CONFIG = {
  USER_ID = 222319587,
  REPOSITORY_ID = 1334849119,
  BRANCH = false,
  REVISION = false,
  ENTRY_POINT = "loader.luau",
  MAX_ATTEMPTS = 3,
  RETRY_DELAYS = { 0.25, 0.75, 1.5 },
  RATE_LIMIT_DEFAULT_DELAY = 5,
  PLAYER_TIMEOUT = 10,
  CACHE_WAIT_TIMEOUT = 60,
  BYPASS_IMMUTABLE_CACHE = false,
  DEBUG = false,
  DOWNLOAD_WORKERS = 12,
  REQUEST_TIMEOUT = 8,
  MAX_PENDING_REQUESTS = 24,
  DOWNLOAD_TIMEOUT = 60,
  PROJECT_PATH = "exodus%20hub/",
  -- Repository endpoints and request policy
  REPOSITORY_API = "https://api.github.com/repositories/",
  RAW_BASE_URL = "https://raw.githubusercontent.com/",
  HEAD_REF_PATH = "/git/ref/heads/",
  CACHE_QUERY_KEY = "exodus_cache",
  API_HEADERS = {
    ["Accept"] = "application/vnd.github+json",
    ["User-Agent"] = "Exodus-Hub-Loader",
    ["Cache-Control"] = "no-cache, no-store",
  },
  RAW_CACHE_HEADERS = { ["Cache-Control"] = "no-cache, no-store" },
  RETRYABLE_HTTP_STATUS = { [408] = true, [425] = true, [429] = true },

  -- Module discovery and lifecycle
  REGISTRY_PATH = "hubs/registry.luau",
  CATALOG_PATH = "hubs/catalog.luau",
  DEFAULT_HUB = { id = "universal", title = "Universal", author = "deltapolinha_2915", notification = "Exodus Hub · Universal carregado." },
  CLEANUP_IGNORE_FAILURE = { invisicam = true },
  CLASH_CONTEXT_MAX_AGE = 0.8,
  CLASH_CLEAR_DELAY = 0.4,
  CLASH_POLL_INTERVAL = 0.06,
  CLEANUP_MODULES = {
    "servers",
    "universal",
    "infinitejump",
    "noclip",
    "fly",
    "invisicam",
    "infinitezoom",
    "speed",
    "gravity",
    "dumper",
    "character",
    "dynamicparry",
    "spam",
    "autodash",
    "autospam",
    "clashstats",
    "autodark",
    "autofierce",
    "autojump",
    "camera",
    "antilag",
    "movement",
    "dash",
    "autoparry",
    "cooldown",
    "remote",
  },

  -- Fallback notifications (seconds and visual defaults)
  NOTIFICATIONS = {
    DEFAULT_DURATION = 2.5,
    STARTUP_WARNING_DURATION = 2.5,
    NAVIGATION_DURATION = 5,
    HUB_LOADED_DURATION = 5,
    DISPLAY_ORDER = 2147483647,
    WIDTH = 320,
    HEIGHT = 38,
    BOTTOM_OFFSET = 24,
    BACKGROUND_TRANSPARENCY = 0.12,
    CRITICAL_COLOR = { 153, 27, 27 },
    INFO_COLOR = { 45, 55, 130 },
    TEXT_COLOR = { 255, 255, 255 },
    CORNER_RADIUS = 10,
    TEXT_PADDING = 10,
    TEXT_SIZE = 13,
    TEXT_FONT = "GothamBold",
    CARD_ZINDEX = 100,
    TEXT_ZINDEX = 101,
  },

  -- Base module manifest
  MODULES = {
    { name = "gamecontext", path = "core/game_integration.luau" },
    { name = "hubapi", path = "core/game_integration.luau" },
    { name = "lifetime", path = "core/lifetime.luau" },
    { name = "profiler", path = "core/diagnostics.luau" },
    { name = "status", path = "core/diagnostics.luau" },
    { name = "runtime", path = "core/game_integration.luau" },
    { name = "permissions", path = "core/permissions.luau" },
    { name = "config", path = "core/config.luau" },
    { name = "uiconfig", path = "ui/definitions.luau" },
    { name = "uitheme", path = "ui/theme.luau" },
    { name = "uiruntime", path = "ui/runtime.luau" },
    { name = "uiicons", path = "ui/icons.luau" },
    { name = "uidisplay", path = "ui/components/basic.luau" },
    { name = "uicontrols", path = "ui/components/basic.luau" },
    { name = "uiinputs", path = "ui/components/inputs.luau" },
    { name = "uiselection", path = "ui/components/basic.luau" },
    { name = "uidropdown", path = "ui/components/dropdown.luau" },
    { name = "uikit", path = "ui/toolkit.luau" },
    { name = "uipages", path = "ui/pages.luau" },
    { name = "uinotifications", path = "ui/controllers/notifications.luau" },
    { name = "uiactions", path = "ui/actions.luau" },
    { name = "state", path = "core/session.luau" },
    { name = "persistence", path = "core/persistence.luau" },
    { name = "diagnostics", path = "core/diagnostics.luau" },
    { name = "utils", path = "core/session.luau" },
    { name = "renderproperties", path = "universal/anti_lag/properties.luau" },
    { name = "renderadapter", path = "universal/anti_lag/antilag.luau" },
    { name = "renderspatial", path = "universal/anti_lag/spatial.luau" },
    { name = "antilag", path = "universal/anti_lag/antilag.luau" },
    { name = "autojump", path = "universal/autojump.luau" },
    { name = "camera", path = "universal/camera.luau" },
    { name = "infinitejump", path = "universal/infinitejump.luau" },
    { name = "noclip", path = "universal/noclip.luau" },
    { name = "fly", path = "universal/fly.luau" },
    { name = "invisicam", path = "universal/camera.luau" },
    { name = "infinitezoom", path = "universal/camera.luau" },
    { name = "speed", path = "universal/speed.luau" },
    { name = "gravity", path = "universal/gravity.luau" },
    { name = "character", path = "core/character.luau" },
    { name = "dumper", path = "universal/dumper.luau" },
    { name = "servers", path = "universal/servers.luau" },
    { name = "uicontext", path = "ui/controllers/context.luau" },
    { name = "uiwindow", path = "ui/controllers/window.luau" },
    { name = "uifloating", path = "ui/controllers/floating.luau" },
    { name = "uinotificationview", path = "ui/controllers/notifications.luau" },
    { name = "uistatus", path = "ui/controllers/information.luau" },
    { name = "uitelemetry", path = "ui/controllers/information.luau" },
    { name = "uiassists", path = "ui/controllers/assists.luau" },
    { name = "uiinput", path = "ui/controllers/input.luau" },
    { name = "uilifecycle", path = "ui/controllers/lifecycle.luau" },
    { name = "ui", path = "ui/interface.luau" },
  },
}

-- module
local Loader = {}
local function printRawError(moduleName, message, filePath)
  local output = ("[%s] %s: %s"):format(tostring(filePath or CONFIG.ENTRY_POINT), tostring(moduleName), tostring(message))
  if type(warn) == "function" then warn(output) elseif type(print) == "function" then print(output) end
end
local function printStartup(message)
  if type(print) == "function" then print(message) end
end
local function fallbackNotification(message, key, kind, duration)
  local players = game:GetService("Players"); local player = players.LocalPlayer
  local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
  if not playerGui then return end
  local gui = playerGui:FindFirstChild("ExodusPersistentNotifications")
  if not gui then
    gui = Instance.new("ScreenGui"); gui.Name = "ExodusPersistentNotifications"
    gui.DisplayOrder = CONFIG.NOTIFICATIONS.DISPLAY_ORDER; gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true; gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    gui.Parent = playerGui
  end
  local layer = gui:FindFirstChild("NotificationLayer")
  if not layer then
    layer = Instance.new("Frame"); layer.Name = "NotificationLayer"
    layer.Size = UDim2.fromScale(1, 1); layer.BackgroundTransparency = 1
    layer.Parent = gui
  end
  local safeKey = tostring(key or "critical"):gsub("[^%w_%-]", "_"); local card = layer:FindFirstChild("Notification_" .. safeKey)
  if not card then
    card = Instance.new("CanvasGroup"); card.Name = "Notification_" .. safeKey
    card:SetAttribute("ExodusNotificationKey", safeKey); card.AnchorPoint = Vector2.new(0.5, 1)
    card.Position = UDim2.new(0.5, 0, 1, -CONFIG.NOTIFICATIONS.BOTTOM_OFFSET); card.Size = UDim2.fromOffset(CONFIG.NOTIFICATIONS.WIDTH, CONFIG.NOTIFICATIONS.HEIGHT)
    card.BackgroundColor3 = Color3.fromRGB(table.unpack(kind == "critical" and CONFIG.NOTIFICATIONS.CRITICAL_COLOR or CONFIG.NOTIFICATIONS.INFO_COLOR)); card.BackgroundTransparency = CONFIG.NOTIFICATIONS.BACKGROUND_TRANSPARENCY
    card.ZIndex = CONFIG.NOTIFICATIONS.CARD_ZINDEX; card.Parent = layer
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, CONFIG.NOTIFICATIONS.CORNER_RADIUS)
    corner.Parent = card; local label = Instance.new("TextLabel")
    label.Name = "Message"; label.Size = UDim2.new(1, -2 * CONFIG.NOTIFICATIONS.TEXT_PADDING, 1, 0)
    label.Position = UDim2.fromOffset(CONFIG.NOTIFICATIONS.TEXT_PADDING, 0); label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(table.unpack(CONFIG.NOTIFICATIONS.TEXT_COLOR)); label.TextSize = CONFIG.NOTIFICATIONS.TEXT_SIZE
    label.Font = Enum.Font[CONFIG.NOTIFICATIONS.TEXT_FONT]; label.TextXAlignment = Enum.TextXAlignment.Center
    label.Parent = card
  end
  local label = card:FindFirstChild("Message")
  if label then
    label.TextColor3 = Color3.fromRGB(table.unpack(CONFIG.NOTIFICATIONS.TEXT_COLOR)); label.RichText = false
    label.TextStrokeTransparency = 1; label.ZIndex = CONFIG.NOTIFICATIONS.TEXT_ZINDEX
    label.Text = tostring(message)
  end
  if duration == nil and key ~= "dumper" then duration = CONFIG.NOTIFICATIONS.DEFAULT_DURATION end
  card.GroupTransparency = 0; card.Visible = true
  local generation = (card:GetAttribute("ExodusNotificationGeneration") or 0) + 1; card:SetAttribute("ExodusNotificationGeneration", generation)
  if duration and duration > 0 then
    task.delay(duration, function()
      if card.Parent and card:GetAttribute("ExodusNotificationGeneration") == generation then card:Destroy() end
    end)
  end
end
local function notifyPersistent(message, key, kind, duration)
  local show = _G.ExodusShowPersistentNotification
  if type(show) == "function" then
    local ok = pcall(show, message, key, kind, duration)
    if ok then return end
  end
  fallbackNotification(message, key, kind, duration)
end
local function clearPersistent(key)
  local clear = _G.ExodusClearPersistentNotification
  if type(clear) == "function" then
    local ok = pcall(clear, key)
    if ok then return end
  end
  local player = game:GetService("Players").LocalPlayer; local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
  local gui = playerGui and playerGui:FindFirstChild("ExodusPersistentNotifications"); local layer = gui and gui:FindFirstChild("NotificationLayer")
  local safeKey = tostring(key or "critical"):gsub("[^%w_%-]", "_"); local card = layer and layer:FindFirstChild("Notification_" .. safeKey)
  if card then card:Destroy() end
end
local function notifyCritical(moduleName)
  notifyPersistent(("Critical error in %s. Check the console."):format(tostring(moduleName or "the hub")), "critical", "critical")
end
local Exodus = type(_G.Exodus) == "table" and _G.Exodus or {}
local Modules = type(Exodus.Modules) == "table" and Exodus.Modules or {}


local PROJECT_PATH = CONFIG.PROJECT_PATH
local BASE_URL
local HttpService = game:GetService("HttpService")
local cacheSequence = 0
local function cacheBuster()
  cacheSequence += 1; return ("%d-%d-%d"):format(os.time(), math.floor(os.clock() * 1000000), cacheSequence)
end
local MODULE_MANIFEST = CONFIG.MODULES
local selectedHub = table.clone(CONFIG.DEFAULT_HUB)
local MODULE_ORDER = {}
local MODULE_BY_NAME = {}
for _, entry in ipairs(MODULE_MANIFEST) do
  MODULE_BY_NAME[entry.name] = entry
  if entry.name ~= "ui" and entry.name ~= "permissions" then MODULE_ORDER[#MODULE_ORDER + 1] = entry.name end
end

-- http
local function getRequestFunction()
  local environment = type(getgenv) == "function" and getgenv() or _G; local synApi = type(environment.syn) == "table" and environment.syn or nil
  local fluxusApi = type(environment.fluxus) == "table" and environment.fluxus or nil
  for _, candidate in ipairs({
    environment.request or false,
    environment.http_request or false,
    synApi and synApi.request or false,
    fluxusApi and fluxusApi.request or false,
  }) do
    if type(candidate) == "function" then return candidate end
  end
  return nil
end
local requestFunction = getRequestFunction()
local function validateExecutor()
  if type(requestFunction) ~= "function" then return false, "executor sem request HTTP suportado" end
  if type(loadstring) ~= "function" then return false, "executor sem loadstring" end
  if type(game) ~= "userdata" and type(game) ~= "table" then return false, "ambiente Roblox indisponível" end
  if type(game.GetService) ~= "function" then return false, "executor sem acesso aos serviços Roblox" end
  return true
end
local function isRetryableHttp(message)
  local statusCode = tonumber(string.match(tostring(message), "HTTP%s+(%d+)"))
  return statusCode == nil or CONFIG.RETRYABLE_HTTP_STATUS[statusCode] == true or (statusCode and statusCode >= 500 and statusCode <= 599)
end
local function waitBeforeRetry(attempt)
  if type(task) == "table" and type(task.wait) == "function" then local delays = CONFIG.RETRY_DELAYS; task.wait(delays[attempt] or delays[#delays] or 0) end
end
local function headerValue(headers, expected)
  for key, value in pairs(type(headers) == "table" and headers or {}) do
    if string.lower(tostring(key)) == string.lower(expected) then return value end
  end
  return nil
end
local function retryAfter(headers)
  local delay = tonumber(headerValue(headers, "retry-after"))
  if delay and delay >= 0 then return delay end
  local reset = tonumber(headerValue(headers, "x-ratelimit-reset")); return reset and math.max(0, reset - os.time()) or CONFIG.RATE_LIMIT_DEFAULT_DELAY
end
local requestState = type(_G.ExodusRequestState) == "table" and _G.ExodusRequestState or { pending = 0 }
if type(requestState.pending) ~= "number" or requestState.pending < 0 then requestState.pending = 0 end
_G.ExodusRequestState = requestState
local function requestOnce(url, headers)
  if not requestFunction then return nil, "Nenhum serviço HTTP disponível" end
  local ok, response
  if type(task) == "table" and type(task.spawn) == "function" and type(task.wait) == "function" then
    if requestState.pending >= CONFIG.MAX_PENDING_REQUESTS then return nil, "Limite de requisições pendentes atingido" end
    local finished = false; requestState.pending += 1
    task.spawn(function()
      local success, result = pcall(requestFunction, { Url = url, Method = "GET", Headers = headers }); requestState.pending -= 1
      ok, response, finished = success, result, true
    end)
    local deadline = os.clock() + CONFIG.REQUEST_TIMEOUT
    while not finished and os.clock() < deadline do
      task.wait()
    end
    if not finished then return nil, "Tempo limite da requisição HTTP" end
  else
    ok, response = pcall(requestFunction, { Url = url, Method = "GET", Headers = headers })
  end
  if not ok then return nil, tostring(response) end
  if type(response) ~= "table" then return nil, "Resposta HTTP inválida" end
  local statusCode = tonumber(response.StatusCode or response.status_code); local responseHeaders = response.Headers or response.headers
  local responseBody = response.Body or response.body or response.ResponseBody
  if not statusCode or statusCode < 200 or statusCode >= 300 then
    local remaining = tonumber(headerValue(responseHeaders, "x-ratelimit-remaining")); local details = string.lower(tostring(responseBody or ""))
    local limited = statusCode == 429
      or (statusCode == 403 and (remaining == 0 or headerValue(responseHeaders, "retry-after") ~= nil or details:find("rate limit", 1, true) ~= nil))
    return nil,
      "HTTP " .. tostring(statusCode or "sem status"),
      limited and { rateLimited = true, retryAfter = retryAfter(responseHeaders), statusCode = statusCode } or {
        statusCode = statusCode,
      }
  end
  if type(responseBody) ~= "string" or responseBody == "" then return nil, "Corpo HTTP vazio ou inválido" end
  return responseBody
end
local function request(url, headers)
  if type(url) ~= "string" or url == "" then return nil, "URL inválida" end
  if not requestFunction then return nil, "Nenhum serviço HTTP disponível" end
  local lastError, lastMeta
  for attempt = 1, CONFIG.MAX_ATTEMPTS do
    local body, err, meta = requestOnce(url, headers)
    if body then return body end
    lastError, lastMeta = err, meta
    if meta and meta.rateLimited then return nil, ("%s (rate limit; retry in %ds)"):format(lastError, math.ceil(meta.retryAfter or CONFIG.RATE_LIMIT_DEFAULT_DELAY)), lastMeta end
    if not isRetryableHttp(lastError) then break end
    if attempt < CONFIG.MAX_ATTEMPTS then waitBeforeRetry(attempt) end
  end
  local message = lastError or "Nenhum serviço HTTP disponível"; return nil, message, lastMeta
end
local function validRevision(value) return type(value) == "string" and #value == 40 and value:match("^[%x]+$") ~= nil end

-- registry
local function register(name, module)
  Modules[name] = module; return module
end
local function clearRegistry()
  for _, name in ipairs(MODULE_ORDER) do
    Modules[name] = nil
  end
  Modules.ui = nil; Modules.permissions = nil
  Modules.Loader = Loader; Exodus.Utils = nil
  Exodus.State = nil; Exodus.Config = nil
  Exodus.ModuleURLs = nil; Exodus.Runtime = nil
  Exodus.Context = nil; Exodus.UI = nil
  Exodus.Diagnostics = nil; Exodus.Version = nil
  Exodus.Revision = nil; Exodus.StartError = nil
  Exodus.StartErrorModule = nil; Exodus.UIReady = false
  Exodus.Started = false; _G.ExodusOnBurst = nil
end
local function cleanupCall(name, action)
  local ok, result, detail = pcall(action)
  if not ok or result == false then printRawError(name, "falha na limpeza: " .. tostring(ok and detail or result)) end
  return ok and result ~= false, result
end
local function stopPreviousRuntime()
  local clean = true; local stop = _G.ExodusUpdateStop
  if type(stop) == "function" then pcall(stop) end
  _G.ExodusUpdateStop = nil; _G.ExodusUpdateToken = nil
  _G.ExodusSourceCache = nil; _G.ExodusRequestedRevision = nil
  local function attempt(name, action)
    local ok, result = cleanupCall(name, action)
    if not ok and not CONFIG.CLEANUP_IGNORE_FAILURE[name] then clean = false end
    return ok, result
  end
  if type(Modules.gameinfo) == "table" and type(Modules.gameinfo.stopMaintenance) == "function" then attempt("gameinfo", Modules.gameinfo.stopMaintenance) end
  for _, name in ipairs(CONFIG.CLEANUP_MODULES) do
    local module = Modules[name]
    if type(module) == "table" then
      if type(module.teardown) == "function" then attempt(name, module.teardown) elseif type(module.resetState) == "function" then attempt(name, module.resetState) end
    end
  end
  local stopped = false
  if type(_G.ExodusStop) == "function" then local ok, result = attempt("Utils", _G.ExodusStop); stopped = ok and result == true end
  if not stopped and type(_G.ExodusUICleanup) == "function" then attempt("UI", _G.ExodusUICleanup) end
  return clean
end

-- loading
local function compile(name, source)
  if type(loadstring) ~= "function" then return nil, "loadstring indisponível" end
  local chunk, compileError = loadstring(source, name)
  if not chunk then return nil, compileError end
  return chunk
end
local executionCache = {}
local function execute(name, chunk)
  local module = executionCache[chunk]
  if not module then module = chunk(); executionCache[chunk] = module end
  if type(module) == "table" and module.__bundle then module = module.__bundle[name] end
  if type(module) ~= "table" then error(name .. " não retornou uma tabela", 2) end
  return module
end
local function resolveLatestRevision()
  local repositoryURL = CONFIG.REPOSITORY_API .. tostring(CONFIG.REPOSITORY_ID)
  local headers = CONFIG.API_HEADERS

  local metadata, metadataError = request(repositoryURL .. "?" .. CONFIG.CACHE_QUERY_KEY .. "=" .. cacheBuster(), headers)
  if not metadata then return nil, metadataError end
  local decoded, repo = pcall(HttpService.JSONDecode, HttpService, metadata)
  if not decoded or type(repo) ~= "table" or type(repo.full_name) ~= "string" or not repo.full_name:match("^[%w_.%-]+/[%w_.%-]+$") then return nil, "Invalid repository metadata" end
  if tonumber(repo.id) ~= CONFIG.REPOSITORY_ID or type(repo.owner) ~= "table" or tonumber(repo.owner.id) ~= CONFIG.USER_ID then return nil, "Repository or owner ID mismatch" end
  local revision = CONFIG.REVISION; local branch = CONFIG.BRANCH or repo.default_branch
  if revision then
    if not validRevision(revision) then return nil, "Invalid configured revision" end
  else
    if type(branch) ~= "string" or branch == "" then return nil, "Invalid repository branch" end
    local encodedBranch = branch:gsub("[^/]+", function(segment) return HttpService:UrlEncode(segment) end)
    local headURL = repositoryURL .. CONFIG.HEAD_REF_PATH .. encodedBranch; local body, requestError = request(headURL .. "?" .. CONFIG.CACHE_QUERY_KEY .. "=" .. cacheBuster(), headers)
    if not body then return nil, requestError end
    local ok, document = pcall(HttpService.JSONDecode, HttpService, body); revision = ok and type(document) == "table" and type(document.object) == "table" and document.object.sha
    if not validRevision(revision) then return nil, "Invalid branch revision: " .. branch end
  end
  BASE_URL = CONFIG.RAW_BASE_URL .. repo.full_name .. "/"
  if CONFIG.DEBUG then printStartup(("[Exodus] Repository %s, revision %s"):format(repo.full_name, revision)) end
  return revision
end
local function buildURLs(revision)
  local root = BASE_URL .. revision .. "/" .. PROJECT_PATH; local urls = {}
  for _, entry in ipairs(MODULE_MANIFEST) do
    urls[entry.name] = root .. entry.path
  end
  return urls
end
local downloadCache = {}
local function loadModule(name, relativePath, url)
  local previous = downloadCache[url]
  if previous then
    local deadline = os.clock() + CONFIG.CACHE_WAIT_TIMEOUT
    while previous.pending do
      if os.clock() >= deadline then return nil, "Tempo limite ao esperar download: " .. relativePath end
      task.wait()
    end
    return previous.chunk, previous.error
  end
  local pending = { pending = true }; downloadCache[url] = pending
  local ok, chunk, detail = pcall(function()
    local downloadURL = CONFIG.BYPASS_IMMUTABLE_CACHE and (url .. "?" .. CONFIG.CACHE_QUERY_KEY .. "=" .. cacheBuster()) or url
    local headers = CONFIG.BYPASS_IMMUTABLE_CACHE and CONFIG.RAW_CACHE_HEADERS or nil; local source, fetchError = request(downloadURL, headers)
    if not source then return nil, fetchError end
    return compile(relativePath, source)
  end)
  if not ok then detail, chunk = tostring(chunk), nil end
  pending.chunk, pending.error, pending.pending = chunk, detail, false
  if not chunk and downloadCache[url] == pending then downloadCache[url] = nil end
  return chunk, detail
end
local function selectHub(revision)
  local root = BASE_URL .. revision .. "/" .. PROJECT_PATH; local registryChunk, registryError = loadModule("hub registry", CONFIG.REGISTRY_PATH, root .. CONFIG.REGISTRY_PATH)
  if not registryChunk then return false, registryError end
  local registry = execute("hub registry", registryChunk); local catalogChunk, catalogError = loadModule("hub catalog", CONFIG.CATALOG_PATH, root .. CONFIG.CATALOG_PATH)
  if not catalogChunk then return false, catalogError end
  local catalog = execute("hub catalog", catalogChunk); selectedHub = registry.select(catalog, game.PlaceId, game.GameId)
  local extra = selectedHub.modules or {}; local common = {}
  for _, entry in ipairs(CONFIG.MODULES) do
    if entry.name ~= "permissions" or selectedHub.permissions == true then common[#common + 1] = entry end
  end
  MODULE_MANIFEST = registry.merge(common, extra); table.clear(MODULE_ORDER)
  table.clear(MODULE_BY_NAME)
  for _, entry in ipairs(MODULE_MANIFEST) do
    MODULE_BY_NAME[entry.name] = entry
    if entry.name ~= "ui" and entry.name ~= "permissions" then MODULE_ORDER[#MODULE_ORDER + 1] = entry.name end
  end
  return true
end
local function orderModulesByDependencies(loaded)
  local positions, state, ordered = {}, {}, {}
  for index, name in ipairs(MODULE_ORDER) do
    positions[name] = index
  end
  local function visit(name)
    if state[name] == 2 then return end
    if state[name] == 1 then error("dependência circular entre módulos: " .. name, 2) end
    if not positions[name] or type(loaded[name]) ~= "table" then error("dependência não inicializável: " .. tostring(name), 2) end
    state[name] = 1; local dependencies = {}
    for _, source in pairs(loaded[name].__contract.requires or {}) do
      if source ~= "permissions" then dependencies[#dependencies + 1] = source end
    end
    table.sort(dependencies, function(a, b) return (positions[a] or math.huge) < (positions[b] or math.huge) end)
    for _, source in ipairs(dependencies) do
      visit(source)
    end
    state[name] = 2; ordered[#ordered + 1] = name
  end
  for _, name in ipairs(MODULE_ORDER) do
    visit(name)
  end
  table.clear(MODULE_ORDER)
  for _, name in ipairs(ordered) do
    if name ~= "character" then MODULE_ORDER[#MODULE_ORDER + 1] = name end
  end
  if loaded.character then MODULE_ORDER[#MODULE_ORDER + 1] = "character" end
end
local function basicLinker()
  local linker = {}
  function linker.validate(name, module)
    assert(type(module.__contract) == "table", name .. ": missing API contract")
    for _, method in ipairs(module.__contract.provides or {}) do
      assert(type(module[method]) == "function", name .. ": missing " .. method)
    end
    return true
  end
  function linker.resolve(name, loaded)
    local dependencies = {}
    for alias, source in pairs(loaded[name].__contract.requires or {}) do
      local provider = assert(loaded[source], "Missing dependency: " .. source)
      for _, method in ipairs((loaded[name].__contract.requiresMethods or {})[alias] or {}) do
        assert(type(provider[method]) == "function", source .. ": missing " .. method)
      end
      dependencies[alias] = provider
    end
    return dependencies
  end
  return linker
end
local activeLoaded
local function loadModules(urls, prepared)
  local loaded, results = {}, prepared or {}
  if not prepared then
    local function load(name)
      local entry = MODULE_BY_NAME[name]; local chunk, loadError = loadModule(name, entry.path, urls[name])
      results[name] = { chunk = chunk, error = loadError }
    end
    if type(task) == "table" and type(task.spawn) == "function" and type(task.wait) == "function" then
      local pending, nextIndex, cancelled = #MODULE_MANIFEST, 1, false; local deadline = os.clock() + CONFIG.DOWNLOAD_TIMEOUT
      for _ = 1, math.min(CONFIG.DOWNLOAD_WORKERS, #MODULE_MANIFEST) do
        task.spawn(function()
          while not cancelled do
            local entry = MODULE_MANIFEST[nextIndex]; nextIndex += 1
            if not entry then return end
            local name = entry.name
            local ok, err = xpcall(function() load(name) end, function(value) return debug.traceback(tostring(value), 2) end)
            if cancelled then return end
            if not ok then results[name] = { error = err } end
            pending -= 1
          end
        end)
      end
      while pending > 0 do
        if os.clock() >= deadline then cancelled = true; return nil, "Loader", "tempo limite ao baixar os módulos" end
        task.wait()
      end
    else
      for _, entry in ipairs(MODULE_MANIFEST) do
        load(entry.name)
      end
    end
    for _, entry in ipairs(MODULE_MANIFEST) do
      local result = results[entry.name]
      if not result or not result.chunk then return nil, entry.name, result and result.error or "carregamento incompleto" end
    end
    return results
  end
  activeLoaded = loaded; local permissions = results.permissions and execute("permissions", results.permissions.chunk) or basicLinker()
  if results.permissions then permissions.configure(selectedHub.permissionPolicy); permissions.validate("permissions", permissions, MODULE_BY_NAME.permissions.path) end
  loaded.permissions = register("permissions", permissions)
  for _, entry in ipairs(MODULE_MANIFEST) do
    local name = entry.name
    if name ~= "permissions" then
      local module = results[name].module or execute(name, results[name].chunk); permissions.validate(name, module, entry.path)
      loaded[name] = register(name, module)
    end
  end
  orderModulesByDependencies(loaded); return loaded
end

-- setup
local function contractOf(module)
  if type(module) ~= "table" then return {} end
  return module.__contract or {}
end
local function collectCharacterBinds(loaded)
  local binds = {}
  for _, name in ipairs(MODULE_ORDER) do
    local module = loaded[name]
    if name ~= "utils" and type(module) == "table" then
      local contract = contractOf(module); local hasBindFlag = contract.bindCharacter == true
      local hasBindFn = type(module.bindCharacter) == "function"; local hasDetachFn = type(module.detachCharacter) == "function"
      if not loaded.gamecontext.supportsModule(name, MODULE_BY_NAME[name].path) then continue end
      if hasBindFlag and hasBindFn and hasDetachFn then binds[#binds + 1] = { name = name, bind = module.bindCharacter, detach = module.detachCharacter }
      elseif hasBindFlag then return nil, name, "contrato bindCharacter incompleto" end
    end
  end
  return binds
end
local function initializeModules(loaded)
  local characterBinds, bindModule, bindError = collectCharacterBinds(loaded)
  if not characterBinds then error(("%s: %s"):format(tostring(bindModule), tostring(bindError)), 2) end
  for _, name in ipairs(MODULE_ORDER) do
    if name ~= "utils" and name ~= "config" and name ~= "uiconfig" and loaded.gamecontext.supportsModule(name, MODULE_BY_NAME[name].path) then
      local module = loaded[name]
      if type(module) ~= "table" or type(module.setup) ~= "function" then error("API interna ausente: " .. name .. ".setup", 2) end
      local deps = loaded.permissions.resolve(name, loaded)
      if name == "character" then deps.characterBinds = characterBinds end
      local initialized, setupError = module.setup(deps)
      if initialized ~= true then error(("%s.setup falhou: %s"):format(name, tostring(setupError or initialized)), 2) end
      if type(module.teardown) == "function" then
        local cleanup = { Connected = true }
        function cleanup:Disconnect()
          if not self.Connected then return end
          self.Connected = false; cleanupCall(name, module.teardown)
        end
        loaded.utils.trackGlobal(cleanup)
      end
    end
  end
  return true
end

-- runtime

-- interface
local function loadInterface(loaded, controls)
  local interface = loaded.ui
  if type(interface) ~= "table" then return false, "UI", "módulo não carregado" end
  if type(interface.setup) ~= "function" then return false, "UI", "setup ausente" end
  local function navigate(method)
    local function status(message) notifyPersistent(message, "server_navigation", "info", CONFIG.NOTIFICATIONS.NAVIGATION_DURATION) end
    local ok, detail = loaded.servers[method](status)
    if not ok then loaded.utils.recordError("Servers", tostring(detail)); notifyPersistent(tostring(detail), "server_navigation", "warning", CONFIG.NOTIFICATIONS.NAVIGATION_DURATION) end
  end
  controls.onRejoin = function() navigate("rejoin") end
  controls.onServerHop = function() navigate("hop") end
  local dependencies = loaded.permissions.resolve("ui", loaded); dependencies.Controls = controls
  local setupResult, setupError = interface.setup(dependencies)
  if setupResult ~= true then return false, "UI", setupError end
  return true
end
local function stopStartup(utils, moduleName, reason)
  utils.stop(); return false, moduleName, reason
end
local function configureModules(loaded, utils, urls)
  for _, entry in ipairs(MODULE_MANIFEST) do
    local module = loaded[entry.name]
    if type(module) == "table" and module.__config and not loaded.config.register(entry.name, module.__config) then return false, "Config", "schema duplicado ou inválido: " .. entry.name end
  end
  if type(utils.setConfigModule) ~= "function" or not utils.setConfigModule(loaded.config) then return false, "Utils", "schema de Config indisponível" end
  local defaults = loaded.config.defaults()
  if type(defaults) ~= "table" then return false, "Config", "defaults inválidos" end
  local configValid, configReason = loaded.config.validate(defaults)
  if configValid ~= true then return false, "Config", configReason end
  utils.setLifecyclePhase("configuring")
  if not utils.setConfig(defaults) then return false, "Utils", "setConfig rejeitou a configuração inicial" end
  if type(utils.loadConfig) == "function" then utils.loadConfig() end
  if not utils.setModuleURLs(urls) then return false, "Utils", "setModuleURLs rejeitou as URLs dos módulos" end
  return true
end

-- startup
local function waitForLocalPlayer(timeout)
  local players = game:GetService("Players")
  if players.LocalPlayer then return true end
  local deadline = os.clock() + timeout
  repeat
    task.wait()
    if players.LocalPlayer then return true end
  until os.clock() >= deadline
  return false, "LocalPlayer indisponível após esperar " .. timeout .. "s"
end
local function clashInProgress(loaded)
  if type(loaded) ~= "table" or type(loaded.utils) ~= "table" or loaded.utils.isActive() ~= true then return false end
  local player = game:GetService("Players").LocalPlayer; local character = player and player.Character
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  if humanoid and humanoid.Health <= 0 then return false end
  if type(loaded.gameinfo) == "table" then
    if type(loaded.deflectgeometry) == "table" and type(loaded.deflectgeometry.getDefensePhysics) == "function" then
      local ok, physics = pcall(loaded.deflectgeometry.getDefensePhysics)
      if ok and type(physics) == "table" and physics.inClash == true then return true end
    end
    if type(loaded.gameinfo.getClashContext) == "function" then
      local ok, context = pcall(loaded.gameinfo.getClashContext)
      if ok and type(context) == "table" and type(context.age) == "number" and context.age >= 0 and context.age <= CONFIG.CLASH_CONTEXT_MAX_AGE then return true end
    end
  end
  if type(loaded.autospam) == "table" and type(loaded.autospam.getActivationContext) == "function" then
    local ok, state = pcall(loaded.autospam.getActivationContext)
    if ok and type(state) == "table" and state.active == true then return true end
  end
  return false
end
local function matchInProgress()
  local loaded = Exodus.Context
  if type(loaded) == "table" and not loaded.gameinfo then return false end
  if type(loaded) ~= "table" or type(loaded.gameinfo) ~= "table" or type(loaded.gameinfo.getGameContext) ~= "function" then return false end
  local ok, context = pcall(loaded.gameinfo.getGameContext); return ok and type(context) == "table" and (context.inMatch == true)
end
local function waitForClashToEnd(onWaiting, isCurrent)
  local loaded = Exodus.Context
  if type(loaded) ~= "table" or type(loaded.utils) ~= "table" then return true end
  local waiting, clearSince = false, nil
  while loaded.utils.isActive() and Exodus.Context == loaded and (not isCurrent or isCurrent()) do
    if not matchInProgress() then return true end
    if clashInProgress(loaded) then
      if not waiting and type(onWaiting) == "function" then onWaiting() end
      waiting, clearSince = true, nil
    else
      if not waiting then return true end
      clearSince = clearSince or os.clock()
      if os.clock() - clearSince >= CONFIG.CLASH_CLEAR_DELAY then return true end
    end
    task.wait(CONFIG.CLASH_POLL_INTERVAL)
  end
  return false
end
local function prepareLoader()
  local revision, revisionError = resolveLatestRevision()
  if not revision then return nil, revisionError end
  return loadModule("reload loader", CONFIG.ENTRY_POINT, BASE_URL .. revision .. "/" .. PROJECT_PATH .. CONFIG.ENTRY_POINT)
end
local reloadInFlight = false
local function reloadLatest(onFailure)
  if reloadInFlight then return false, "reload already in progress" end
  reloadInFlight = true; local session = _G.ExodusLoaderSessionToken
  task.spawn(function()
    local ok, detail = xpcall(function()
      local chunk, prepareError = prepareLoader()
      if not chunk then error(prepareError, 0) end
      if _G.ExodusLoaderSessionToken ~= session then return end
      chunk()
    end, function(err) return debug.traceback(tostring(err), 2) end)
    reloadInFlight = false
    if not ok then
      printRawError("Loader", detail)
      if type(onFailure) == "function" then task.defer(onFailure, detail) end
    end
  end)
  return true
end
local startupPerformed = false
local function startInternal()
  local wasStarted = Exodus.Started == true; local version, revisionError = resolveLatestRevision()
  if not version then return false, "Loader", revisionError or "revisão atual indisponível" end
  local selected, selectionError = selectHub(version)
  if not selected then return false, "Loader", selectionError end
  local urls = buildURLs(version); local prepared, prepareModule, prepareError = loadModules(urls)
  if not prepared then return false, prepareModule, prepareError end
  local playerReady, playerError = waitForLocalPlayer(CONFIG.PLAYER_TIMEOUT)
  if not playerReady then return false, "Loader", playerError end
  printStartup("Exodus: Initializing..."); _G.ExodusShutdownReason = "restart"
  if not stopPreviousRuntime() then _G.ExodusShutdownReason = nil; return false, "Loader", "failed to stop the previous session" end
  _G.ExodusShutdownReason = nil; startupPerformed = true
  clearRegistry(); local loaded, moduleName, loadError = loadModules(urls, prepared)
  if not loaded then return false, moduleName, loadError end
  activeLoaded = loaded; loaded.gamecontext.configure(selectedHub)
  loaded.hubapi.configure(loaded); local utils = loaded.utils
  if type(utils.start) ~= "function" or type(utils.setLifecyclePhase) ~= "function" then return false, "Utils", "contrato de inicialização incompleto" end
  utils.configure(loaded.permissions.resolve("utils", loaded)); utils.start()
  utils.setLifecyclePhase("loading"); loaded.status.configure(loaded, utils.recordError)
  Exodus.Utils = utils; Exodus.State = utils.getStateSnapshot()
  local configured, configModuleName, configError = configureModules(loaded, utils, urls)
  if not configured then return stopStartup(utils, configModuleName, configError) end
  Exodus.Config = utils.getConfigSnapshot(); Exodus.ModuleURLs = utils.getModuleURLsSnapshot()
  utils.setLifecyclePhase("initializing"); local modulesReady, failedModule, modulesError = initializeModules(loaded)
  if not modulesReady then return stopStartup(utils, failedModule, modulesError) end
  if not utils.setDiagnosticsModules(loaded) then return stopStartup(utils, "Utils", "setDiagnosticsModules rejeitou os módulos") end
  utils.setLifecyclePhase("binding"); local runtime, runtimeError = loaded.runtime.bind(loaded, MODULE_ORDER, HttpService, printRawError)
  if type(runtime) ~= "table" then return stopStartup(utils, "Runtime", runtimeError) end
  Exodus.Runtime = runtime
  _G.ExodusOnBurst = if loaded.autoparry then loaded.autoparry.fire else nil
  local uiReady, uiModule, uiError = loadInterface(loaded, {
    onAutoDarkChanged = function() loaded.autodark.sync() end,
    onAutoJumpChanged = function() loaded.autojump.sync() end,
    onUpDash = function()
      local ok, err = loaded.movement.upDash()
      if not ok then utils.recordError("UpDash", err or "Dash indisponível") end
    end,
    onUniversalToggle = function(feature, enabled)
      local module = loaded[feature:lower()]
      if not module then return end
      local ok, err = module.setEnabled(enabled)
      if not ok then utils.recordError("Universal." .. tostring(feature), err or "falha ao alterar recurso") end
    end,
    onUniversalValue = function(feature, value)
      local module = loaded[feature:lower()]
      if not module or type(module.setValue) ~= "function" then return end
      local ok, err = module.setValue(value)
      if not ok then utils.recordError("Universal." .. tostring(feature), err or "falha ao alterar valor") end
    end,
    onPanic = function()
      utils.setConfig({ AutoParry = false, AutoSpam = false }); utils.stopAllSpam()
      if loaded.autospam then loaded.autospam.stopSpam() end
    end,
    onClose = function() utils.stop() end,
    onReload = reloadLatest,
    waitForSafeShutdown = function()
      local ready = waitForClashToEnd(function() notifyPersistent("Waiting for clash to end before closing", "shutdown", "info") end)
      clearPersistent("shutdown"); return ready
    end,
  })
  if not uiReady then return stopStartup(utils, uiModule, uiError) end
  Exodus.Hub = table.clone(selectedHub); notifyPersistent(selectedHub.notification or ("Exodus Hub · " .. selectedHub.title .. " carregado."), "hub_loaded", "info", CONFIG.NOTIFICATIONS.HUB_LOADED_DURATION)
  Exodus.Context = loaded; Exodus.UIReady = uiReady == true
  Exodus.UI = Modules.ui; utils.setLifecyclePhase(uiReady == true and "ready" or "runtime_ready")
  Exodus.Started = true; Exodus.Version = utils.version()
  Exodus.Revision = version; _G.ExodusLastLoadedRevision = version
  if wasStarted then printStartup("Exodus: Reloaded.") else printStartup("Exodus: Initialized.") end
  return true
end

-- rollback
local function rollbackLoaded(loaded)
  if type(loaded) ~= "table" then return end
  for index = #MODULE_ORDER, 1, -1 do
    local name = MODULE_ORDER[index]; local module = loaded[name]
    if type(module) == "table" then
      if type(module.teardown) == "function" then cleanupCall(name, module.teardown)
      elseif type(module.detachCharacter) == "function" then cleanupCall(name, module.detachCharacter)
      elseif type(module.resetState) == "function" then cleanupCall(name, module.resetState) end
    end
  end
  if type(loaded.gameinfo) == "table" and type(loaded.gameinfo.stopMaintenance) == "function" then cleanupCall("gameinfo", loaded.gameinfo.stopMaintenance) end
  if type(loaded.utils) == "table" and type(loaded.utils.stop) == "function" then cleanupCall("utils", loaded.utils.stop) end
end
local startLock = false
local startToken = {}
function Loader.start()
  if startLock or _G.ExodusLoaderStartToken then
    local message = "Inicialização já em andamento. Aguarde o carregamento atual."
    if type(warn) == "function" then warn("[Exodus] " .. message) else printStartup(message) end
    pcall(notifyPersistent, message, "startup_in_progress", "warning", CONFIG.NOTIFICATIONS.STARTUP_WARNING_DURATION); return true, nil, nil, "in_progress"
  end
  local ready, reason = validateExecutor()
  if not ready then return false, "Loader", reason end
  startLock = true; startupPerformed = false
  _G.ExodusLoaderStartToken = startToken; Exodus.Modules = Modules
  _G.Exodus = Exodus; _G.ExodusModules = Modules
  local ok, started, moduleName, startError = xpcall(startInternal, function(err) return debug.traceback(tostring(err), 2) end)
  startLock = false
  if _G.ExodusLoaderStartToken == startToken then _G.ExodusLoaderStartToken = nil end
  if not ok then
    if startupPerformed then rollbackLoaded(activeLoaded); clearRegistry() end
    activeLoaded = nil; return false, "Loader", started
  end
  if started ~= true then
    if startupPerformed then rollbackLoaded(activeLoaded); clearRegistry() end
    activeLoaded = nil; return started, moduleName, startError
  end
  if startupPerformed then
    Exodus.Loader = Loader; Modules.Loader = Loader
    _G.ExodusLoaderSessionToken = startToken
  end
  activeLoaded = nil; return started, moduleName, startError
end
local function startSafely()
  local started, moduleName, startError, status = Loader.start()
  if status == "in_progress" then return nil end
  if started ~= true then
    moduleName = moduleName or "Loader"; startError = startError or started
    local entry = MODULE_BY_NAME[moduleName]; printRawError(moduleName, startError, entry and entry.path or CONFIG.ENTRY_POINT)
    notifyCritical(moduleName)
    Loader.lastError = startError
    Loader.lastErrorModule = moduleName
    Exodus.StartError = startError
    Exodus.StartErrorModule = moduleName; error(("%s: %s"):format(tostring(moduleName), tostring(startError)), 2)
  end
  Loader.lastError = nil; Loader.lastErrorModule = nil
  Exodus.StartError = nil; Exodus.StartErrorModule = nil
  return true
end
local started = startSafely()
if started ~= nil then Exodus.Started = started == true end

return Loader
