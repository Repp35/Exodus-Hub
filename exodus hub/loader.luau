-- [[ loader ]]
--!optimize 2

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
  REGISTRY_PATH = "hubs/registry.luau",
  CATALOG_PATH = "hubs/catalog.luau",
  MANIFEST_PATH = "core/catalog.luau",
  NOTIFICATIONS = {
    DEFAULT_DURATION = 2.5,
    STARTUP_WARNING_DURATION = 2.5,
    NAVIGATION_DURATION = 5,
    HUB_LOADED_DURATION = 5,
    DISPLAY_ORDER = 2147483647,
    WIDTH = 320,
    HEIGHT = 46,
    BOTTOM_OFFSET = 24,
    BACKGROUND_TRANSPARENCY = 0.12,
    CRITICAL_COLOR = { 153, 27, 27 },
    INFO_COLOR = { 45, 55, 130 },
    TEXT_COLOR = { 255, 255, 255 },
    CORNER_RADIUS = 10,
    TEXT_PADDING = 10,
    TEXT_SIZE = 11,
    TEXT_FONT = "GothamMedium",
    CARD_ZINDEX = 100,
    TEXT_ZINDEX = 101,
  },
}

-- module
local Loader = {}
local function printRawError(moduleName, message, filePath)
  local output = ("[%s] %s: %s"):format(tostring(filePath or CONFIG.ENTRY_POINT), tostring(moduleName), tostring(message))
  if type(warn) == "function" then
    warn(output)
  elseif type(print) == "function" then
    print(output)
  end
end
local function printStartup(message)
  if type(print) == "function" then
    print(message)
  end
end
local function fallbackNotification(message, key, kind, duration)
  local players = game:GetService("Players")
  local player = players.LocalPlayer
  local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
  if not playerGui then
    return
  end
  local gui = playerGui:FindFirstChild("ExodusPersistentNotifications")
  if not gui then
    gui = Instance.new("ScreenGui")
    gui.Name = "ExodusPersistentNotifications"
    gui.DisplayOrder = CONFIG.NOTIFICATIONS.DISPLAY_ORDER
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    gui.Parent = playerGui
  end
  local layer = gui:FindFirstChild("NotificationLayer")
  if not layer then
    layer = Instance.new("Frame")
    layer.Name = "NotificationLayer"
    layer.Size = UDim2.fromScale(1, 1)
    layer.BackgroundTransparency = 1
    layer.Parent = gui
  end
  local safeKey = tostring(key or "critical"):gsub("[^%w_%-]", "_")
  local card = layer:FindFirstChild("Notification_" .. safeKey)
  if not card then
    card = Instance.new("CanvasGroup")
    card.Name = "Notification_" .. safeKey
    card:SetAttribute("ExodusNotificationKey", safeKey)
    card.AnchorPoint = Vector2.new(0.5, 1)
    card.Position = UDim2.new(0.5, 0, 1, -CONFIG.NOTIFICATIONS.BOTTOM_OFFSET)
    card.Size = UDim2.fromOffset(CONFIG.NOTIFICATIONS.WIDTH, CONFIG.NOTIFICATIONS.HEIGHT)
    card.BackgroundColor3 = Color3.fromRGB(table.unpack(kind == "critical" and CONFIG.NOTIFICATIONS.CRITICAL_COLOR or CONFIG.NOTIFICATIONS.INFO_COLOR))
    card.BackgroundTransparency = CONFIG.NOTIFICATIONS.BACKGROUND_TRANSPARENCY
    card.ZIndex = CONFIG.NOTIFICATIONS.CARD_ZINDEX
    card.Parent = layer
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, CONFIG.NOTIFICATIONS.CORNER_RADIUS)
    corner.Parent = card
    local label = Instance.new("TextLabel")
    label.Name = "Message"
    label.Size = UDim2.new(1, -2 * CONFIG.NOTIFICATIONS.TEXT_PADDING, 1, 0)
    label.Position = UDim2.fromOffset(CONFIG.NOTIFICATIONS.TEXT_PADDING, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(table.unpack(CONFIG.NOTIFICATIONS.TEXT_COLOR))
    label.TextSize = CONFIG.NOTIFICATIONS.TEXT_SIZE
    label.Font = Enum.Font[CONFIG.NOTIFICATIONS.TEXT_FONT]
    label.TextWrapped = true
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Parent = card
  end
  local label = card:FindFirstChild("Message")
  if label then
    label.TextColor3 = Color3.fromRGB(table.unpack(CONFIG.NOTIFICATIONS.TEXT_COLOR))
    label.RichText = false
    label.TextStrokeTransparency = 1
    label.ZIndex = CONFIG.NOTIFICATIONS.TEXT_ZINDEX
    label.Text = tostring(message)
  end
  if duration == nil and key ~= "dumper" then
    duration = CONFIG.NOTIFICATIONS.DEFAULT_DURATION
  end
  card.GroupTransparency = 1
  card.Visible = true
  game:GetService("TweenService"):Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
  local generation = (card:GetAttribute("ExodusNotificationGeneration") or 0) + 1
  card:SetAttribute("ExodusNotificationGeneration", generation)
  if duration and duration > 0 then
    task.delay(duration, function()
      if card.Parent and card:GetAttribute("ExodusNotificationGeneration") == generation then
        game:GetService("TweenService"):Create(card, TweenInfo.new(0.3), { GroupTransparency = 1 }):Play()
        task.delay(0.3, function()
          if card.Parent and card:GetAttribute("ExodusNotificationGeneration") == generation then
            card:Destroy()
          end
        end)
      end
    end)
  end
end
local function notifyPersistent(message, key, kind, duration)
  local show = _G.ExodusShowPersistentNotification
  if type(show) == "function" then
    local ok = pcall(show, message, key, kind, duration)
    if ok then
      return
    end
  end
  fallbackNotification(message, key, kind, duration)
end
local function clearPersistent(key)
  local clear = _G.ExodusClearPersistentNotification
  if type(clear) == "function" then
    local ok = pcall(clear, key)
    if ok then
      return
    end
  end
  local player = game:GetService("Players").LocalPlayer
  local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
  local gui = playerGui and playerGui:FindFirstChild("ExodusPersistentNotifications")
  local layer = gui and gui:FindFirstChild("NotificationLayer")
  local safeKey = tostring(key or "critical"):gsub("[^%w_%-]", "_")
  local card = layer and layer:FindFirstChild("Notification_" .. safeKey)
  if card then
    local generation = (card:GetAttribute("ExodusNotificationGeneration") or 0) + 1
    card:SetAttribute("ExodusNotificationGeneration", generation)
    game:GetService("TweenService"):Create(card, TweenInfo.new(0.3), { GroupTransparency = 1 }):Play()
    task.delay(0.3, function()
      if card.Parent and card:GetAttribute("ExodusNotificationGeneration") == generation then
        card:Destroy()
      end
    end)
  end
end
local function notifyCritical(moduleName)
  notifyPersistent(("Critical error in %s. Check the console."):format(tostring(moduleName or "the hub")), "critical", "critical")
end
local Exodus = type(_G.Exodus) == "table" and _G.Exodus or {}
local Modules = type(Exodus.Modules) == "table" and Exodus.Modules or {}
local PROJECT_PATH = CONFIG.PROJECT_PATH
local BASE_URL = _G.ExodusRepositoryBaseURL
local HttpService = game:GetService("HttpService")
local cacheSequence = 0
local function cacheBuster()
  cacheSequence += 1
  return ("%d-%d-%d"):format(os.time(), math.floor(os.clock() * 1000000), cacheSequence)
end
local MODULE_MANIFEST = {}
local selectedHub = {}
local MODULE_ORDER = {}
local MODULE_BY_NAME = {}
for _, entry in ipairs(MODULE_MANIFEST) do
  MODULE_BY_NAME[entry.name] = entry
  if entry.name ~= "ui" and entry.name ~= "permissions" then
    MODULE_ORDER[#MODULE_ORDER + 1] = entry.name
  end
end

-- http
local function getRequestFunction()
  local environment = type(getgenv) == "function" and getgenv() or _G
  local synApi = type(environment.syn) == "table" and environment.syn or nil
  local fluxusApi = type(environment.fluxus) == "table" and environment.fluxus or nil
  for _, candidate in ipairs({
    environment.request or false,
    environment.http_request or false,
    synApi and synApi.request or false,
    fluxusApi and fluxusApi.request or false,
  }) do
    if type(candidate) == "function" then
      return candidate
    end
  end
  return nil
end
local requestFunction = getRequestFunction()
local function validateExecutor()
  if type(requestFunction) ~= "function" then
    return false, "executor sem request HTTP suportado"
  end
  if type(loadstring) ~= "function" then
    return false, "executor sem loadstring"
  end
  if type(game) ~= "userdata" and type(game) ~= "table" then
    return false, "ambiente Roblox indisponível"
  end
  if type(game.GetService) ~= "function" then
    return false, "executor sem acesso aos serviços Roblox"
  end
  return true
end
local function isRetryableHttp(message)
  local statusCode = tonumber(string.match(tostring(message), "HTTP%s+(%d+)"))
  return statusCode == nil or CONFIG.RETRYABLE_HTTP_STATUS[statusCode] == true or (statusCode and statusCode >= 500 and statusCode <= 599)
end
local function waitBeforeRetry(attempt)
  if type(task) == "table" and type(task.wait) == "function" then
    local delays = CONFIG.RETRY_DELAYS
    task.wait(delays[attempt] or delays[#delays] or 0)
  end
end
local function headerValue(headers, expected)
  for key, value in pairs(type(headers) == "table" and headers or {}) do
    if string.lower(tostring(key)) == string.lower(expected) then
      return value
    end
  end
  return nil
end
local function retryAfter(headers)
  local delay = tonumber(headerValue(headers, "retry-after"))
  if delay and delay >= 0 then
    return delay
  end
  local reset = tonumber(headerValue(headers, "x-ratelimit-reset"))
  return reset and math.max(0, reset - os.time()) or CONFIG.RATE_LIMIT_DEFAULT_DELAY
end
local requestState = type(_G.ExodusRequestState) == "table" and _G.ExodusRequestState or { pending = 0 }
if type(requestState.pending) ~= "number" or requestState.pending < 0 then
  requestState.pending = 0
end
_G.ExodusRequestState = requestState
local function requestOnce(url, headers)
  if not requestFunction then
    return nil, "Nenhum serviço HTTP disponível"
  end
  local ok, response
  if type(task) == "table" and type(task.spawn) == "function" and type(task.wait) == "function" then
    if requestState.pending >= CONFIG.MAX_PENDING_REQUESTS then
      return nil, "Limite de requisições pendentes atingido"
    end
    local finished = false
    requestState.pending += 1
    task.spawn(function()
      local success, result = pcall(requestFunction, { Url = url, Method = "GET", Headers = headers })
      requestState.pending -= 1
      ok, response, finished = success, result, true
    end)
    local deadline = os.clock() + CONFIG.REQUEST_TIMEOUT
    while not finished and os.clock() < deadline do
      task.wait()
    end
    if not finished then
      return nil, "Tempo limite da requisição HTTP"
    end
  else
    ok, response = pcall(requestFunction, { Url = url, Method = "GET", Headers = headers })
  end
  if not ok then
    return nil, tostring(response)
  end
  if type(response) ~= "table" then
    return nil, "Resposta HTTP inválida"
  end
  local statusCode = tonumber(response.StatusCode or response.status_code)
  local responseHeaders = response.Headers or response.headers
  local responseBody = response.Body or response.body or response.ResponseBody
  if not statusCode or statusCode < 200 or statusCode >= 300 then
    local remaining = tonumber(headerValue(responseHeaders, "x-ratelimit-remaining"))
    local details = string.lower(tostring(responseBody or ""))
    local limited = statusCode == 429
      or (statusCode == 403 and (remaining == 0 or headerValue(responseHeaders, "retry-after") ~= nil or details:find("rate limit", 1, true) ~= nil))
    return nil,
      "HTTP " .. tostring(statusCode or "sem status"),
      limited and { rateLimited = true, retryAfter = retryAfter(responseHeaders), statusCode = statusCode } or {
        statusCode = statusCode,
      }
  end
  if type(responseBody) ~= "string" or responseBody == "" then
    return nil, "Corpo HTTP vazio ou inválido"
  end
  return responseBody
end
local function request(url, headers)
  if type(url) ~= "string" or url == "" then
    return nil, "URL inválida"
  end
  if not requestFunction then
    return nil, "Nenhum serviço HTTP disponível"
  end
  local lastError, lastMeta
  for attempt = 1, CONFIG.MAX_ATTEMPTS do
    local body, err, meta = requestOnce(url, headers)
    if body then
      return body
    end
    lastError, lastMeta = err, meta
    if meta and meta.rateLimited then
      return nil, ("%s (rate limit; retry in %ds)"):format(lastError, math.ceil(meta.retryAfter or CONFIG.RATE_LIMIT_DEFAULT_DELAY)), lastMeta
    end
    if not isRetryableHttp(lastError) then
      break
    end
    if attempt < CONFIG.MAX_ATTEMPTS then
      waitBeforeRetry(attempt)
    end
  end
  local message = lastError or "Nenhum serviço HTTP disponível"
  return nil, message, lastMeta
end
local function validRevision(value) return type(value) == "string" and #value == 40 and value:match("^[%x]+$") ~= nil end

-- registry
local function clearRegistry()
  table.clear(Modules)
  Modules.Loader = Loader
  Exodus.Utils = nil
  Exodus.State = nil
  Exodus.Config = nil
  Exodus.ModuleURLs = nil
  Exodus.Runtime = nil
  Exodus.Context = nil
  Exodus.UI = nil
  Exodus.Diagnostics = nil
  Exodus.Version = nil
  Exodus.Revision = nil
  Exodus.StartError = nil
  Exodus.StartErrorModule = nil
  Exodus.UIReady = false
  Exodus.Started = false
end
local function cleanupCall(name, action)
  local ok, result, detail = pcall(action)
  if not ok or result == false then
    printRawError(name, "falha na limpeza: " .. tostring(ok and detail or result))
  end
  return ok and result ~= false, result
end
local function stopPreviousRuntime()
  if type(_G.ExodusStop) == "function" then
    local ok, result = cleanupCall("Session", _G.ExodusStop)
    return ok and result ~= false
  end
  if type(_G.ExodusUICleanup) == "function" then
    return cleanupCall("UI", _G.ExodusUICleanup)
  end
  return true
end

-- loading
local function compile(name, source)
  if type(loadstring) ~= "function" then
    return nil, "loadstring indisponível"
  end
  local chunk, compileError = loadstring(source, name)
  if not chunk then
    return nil, compileError
  end
  return chunk
end
local executionCache = {}
local function execute(name, chunk)
  local module = executionCache[chunk]
  if not module then
    module = chunk()
    executionCache[chunk] = module
  end
  if type(module) == "table" and module.__bundle then
    module = module.__bundle[name]
  end
  if type(module) ~= "table" then
    error(name .. " não retornou uma tabela", 2)
  end
  return module
end
local repositoryMetadata
local function resolveLatestRevision()
  local repositoryURL = CONFIG.REPOSITORY_API .. tostring(CONFIG.REPOSITORY_ID)
  local headers = CONFIG.API_HEADERS
  local repo = repositoryMetadata
  if not repo then
    local metadata, metadataError = request(repositoryURL .. "?" .. CONFIG.CACHE_QUERY_KEY .. "=" .. cacheBuster(), headers)
    if not metadata then
      return nil, metadataError
    end
    local decoded
    decoded, repo = pcall(HttpService.JSONDecode, HttpService, metadata)
    if not decoded or type(repo) ~= "table" or type(repo.full_name) ~= "string" or not repo.full_name:match("^[%w_.%-]+/[%w_.%-]+$") then
      return nil, "Invalid repository metadata"
    end
    if tonumber(repo.id) ~= CONFIG.REPOSITORY_ID or type(repo.owner) ~= "table" or tonumber(repo.owner.id) ~= CONFIG.USER_ID then
      return nil, "Repository or owner ID mismatch"
    end
    repositoryMetadata = repo
  end
  local revision = CONFIG.REVISION
  local branch = CONFIG.BRANCH or repo.default_branch
  if revision then
    if not validRevision(revision) then
      return nil, "Invalid configured revision"
    end
  else
    if type(branch) ~= "string" or branch == "" then
      return nil, "Invalid repository branch"
    end
    local encodedBranch = branch:gsub("[^/]+", function(segment) return HttpService:UrlEncode(segment) end)
    local headURL = repositoryURL .. CONFIG.HEAD_REF_PATH .. encodedBranch
    local body, requestError = request(headURL .. "?" .. CONFIG.CACHE_QUERY_KEY .. "=" .. cacheBuster(), headers)
    if not body then
      return nil, requestError
    end
    local ok, document = pcall(HttpService.JSONDecode, HttpService, body)
    revision = ok and type(document) == "table" and type(document.object) == "table" and document.object.sha
    if not validRevision(revision) then
      return nil, "Invalid branch revision: " .. branch
    end
  end
  BASE_URL = CONFIG.RAW_BASE_URL .. repo.full_name .. "/"
  _G.ExodusRepositoryBaseURL = BASE_URL
  if CONFIG.DEBUG then
    printStartup(("[Exodus] Repository %s, revision %s"):format(repo.full_name, revision))
  end
  return revision
end
local function buildURLs(revision)
  local root = BASE_URL .. revision .. "/" .. PROJECT_PATH
  local urls = {}
  for _, entry in ipairs(MODULE_MANIFEST) do
    urls[entry.name] = root .. entry.path
  end
  return urls
end
local downloadCache = {}
local sourceCache = type(_G.ExodusSourceCache) == "table" and _G.ExodusSourceCache or { sources = {}, bytes = 0 }
_G.ExodusSourceCache = sourceCache
local function loadModule(name, relativePath, url, fingerprint)
  local cacheKey = fingerprint and (relativePath .. ":" .. fingerprint) or url
  local previous = downloadCache[url]
  if previous then
    local deadline = os.clock() + CONFIG.CACHE_WAIT_TIMEOUT
    while previous.pending do
      if os.clock() >= deadline then
        return nil, "Tempo limite ao esperar download: " .. relativePath
      end
      task.wait()
    end
    return previous.chunk, previous.error
  end
  local pending = { pending = true }
  downloadCache[url] = pending
  local ok, chunk, detail = pcall(function()
    local downloadURL = CONFIG.BYPASS_IMMUTABLE_CACHE and (url .. "?" .. CONFIG.CACHE_QUERY_KEY .. "=" .. cacheBuster()) or url
    local headers = CONFIG.BYPASS_IMMUTABLE_CACHE and CONFIG.RAW_CACHE_HEADERS or nil
    local source, fetchError = sourceCache.sources[cacheKey], nil
    if not source or CONFIG.BYPASS_IMMUTABLE_CACHE then
      source, fetchError = request(downloadURL, headers)
    end
    if not source then
      return nil, fetchError
    end
    local chunk, compileError = compile(relativePath, source)
    if not chunk then
      if sourceCache.sources[cacheKey] then
        sourceCache.bytes -= #sourceCache.sources[cacheKey]
        sourceCache.sources[cacheKey] = nil
      end
      return nil, compileError
    end
    if not sourceCache.sources[cacheKey] then
      if sourceCache.bytes + #source > 8 * 1024 * 1024 then
        sourceCache.sources, sourceCache.bytes = {}, 0
      end
      sourceCache.bytes += #source
      sourceCache.sources[cacheKey] = source
    end
    return chunk
  end)
  if not ok then
    detail, chunk = tostring(chunk), nil
  end
  pending.chunk, pending.error, pending.pending = chunk, detail, false
  if not chunk and downloadCache[url] == pending then
    downloadCache[url] = nil
  end
  return chunk, detail
end
local function selectHub(revision)
  local root = BASE_URL .. revision .. "/" .. PROJECT_PATH
  local registryChunk, registryError = loadModule("hub registry", CONFIG.REGISTRY_PATH, root .. CONFIG.REGISTRY_PATH)
  if not registryChunk then
    return false, registryError
  end
  local registry = execute("hub registry", registryChunk)
  local catalogChunk, catalogError = loadModule("hub catalog", CONFIG.CATALOG_PATH, root .. CONFIG.CATALOG_PATH)
  if not catalogChunk then
    return false, catalogError
  end
  local catalog = execute("hub catalog", catalogChunk)
  selectedHub = registry.select(catalog, game.PlaceId, game.GameId)
  local manifestChunk, manifestError = loadModule("shared manifest", CONFIG.MANIFEST_PATH, root .. CONFIG.MANIFEST_PATH)
  if not manifestChunk then
    return false, manifestError
  end
  local extra = selectedHub.modules or {}
  local common = {}
  for _, entry in ipairs(execute("shared manifest", manifestChunk)) do
    if entry.name ~= "permissions" or selectedHub.permissions == true then
      common[#common + 1] = entry
    end
  end
  MODULE_MANIFEST = registry.merge(common, extra)
  table.clear(MODULE_ORDER)
  table.clear(MODULE_BY_NAME)
  for _, entry in ipairs(MODULE_MANIFEST) do
    MODULE_BY_NAME[entry.name] = entry
    if entry.name ~= "ui" and entry.name ~= "permissions" then
      MODULE_ORDER[#MODULE_ORDER + 1] = entry.name
    end
  end
  return true
end
local function orderModulesByDependencies(loaded)
  local positions, state, ordered = {}, {}, {}
  for index, name in ipairs(MODULE_ORDER) do
    positions[name] = index
  end
  local function visit(name)
    if state[name] == 2 then
      return
    end
    if state[name] == 1 then
      error("dependência circular entre módulos: " .. name, 2)
    end
    if not positions[name] or type(loaded[name]) ~= "table" then
      error("dependência não inicializável: " .. tostring(name), 2)
    end
    state[name] = 1
    local dependencies = {}
    for _, source in pairs(loaded[name].__contract.requires or {}) do
      if source ~= "permissions" then
        dependencies[#dependencies + 1] = source
      end
    end
    table.sort(dependencies, function(a, b) return (positions[a] or math.huge) < (positions[b] or math.huge) end)
    for _, source in ipairs(dependencies) do
      visit(source)
    end
    state[name] = 2
    ordered[#ordered + 1] = name
  end
  for _, name in ipairs(MODULE_ORDER) do
    visit(name)
  end
  table.clear(MODULE_ORDER)
  for _, name in ipairs(ordered) do
    if name ~= "character" then
      MODULE_ORDER[#MODULE_ORDER + 1] = name
    end
  end
  if loaded.character then
    MODULE_ORDER[#MODULE_ORDER + 1] = "character"
  end
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
      local entry = MODULE_BY_NAME[name]
      local chunk, loadError = loadModule(name, entry.path, urls[name], entry.hash)
      results[name] = { chunk = chunk, error = loadError }
    end
    if type(task) == "table" and type(task.spawn) == "function" and type(task.wait) == "function" then
      local pending, nextIndex, cancelled = #MODULE_MANIFEST, 1, false
      local deadline = os.clock() + CONFIG.DOWNLOAD_TIMEOUT
      for _ = 1, math.min(CONFIG.DOWNLOAD_WORKERS, #MODULE_MANIFEST) do
        task.spawn(function()
          while not cancelled do
            local entry = MODULE_MANIFEST[nextIndex]
            nextIndex += 1
            if not entry then
              return
            end
            local name = entry.name
            local ok, err = xpcall(function() load(name) end, function(value) return debug.traceback(tostring(value), 2) end)
            if cancelled then
              return
            end
            if not ok then
              results[name] = { error = err }
            end
            pending -= 1
          end
        end)
      end
      while pending > 0 do
        if os.clock() >= deadline then
          cancelled = true
          return nil, "Loader", "tempo limite ao baixar os módulos"
        end
        task.wait()
      end
    else
      for _, entry in ipairs(MODULE_MANIFEST) do
        load(entry.name)
      end
    end
    for _, entry in ipairs(MODULE_MANIFEST) do
      local result = results[entry.name]
      if not result or not result.chunk then
        return nil, entry.name, result and result.error or "carregamento incompleto"
      end
    end
    return results
  end
  local permissions = results.permissions and execute("permissions", results.permissions.chunk) or basicLinker()
  if results.permissions then
    permissions.configure(selectedHub.permissionPolicy)
    permissions.validate("permissions", permissions, MODULE_BY_NAME.permissions.path)
  end
  loaded.permissions = permissions
  for _, entry in ipairs(MODULE_MANIFEST) do
    local name = entry.name
    if name ~= "permissions" then
      local module = results[name].module or execute(name, results[name].chunk)
      permissions.validate(name, module, entry.path)
      loaded[name] = module
    end
  end
  orderModulesByDependencies(loaded)
  return loaded
end

-- startup
local function waitForLocalPlayer(timeout)
  local players = game:GetService("Players")
  if players.LocalPlayer then
    return true
  end
  local deadline = os.clock() + timeout
  repeat
    task.wait()
    if players.LocalPlayer then
      return true
    end
  until os.clock() >= deadline
  return false, "LocalPlayer indisponível após esperar " .. timeout .. "s"
end
local function prepareLoader()
  local revision, revisionError = resolveLatestRevision()
  if not revision then
    return nil, revisionError
  end
  local chunk, err = loadModule("reload loader", CONFIG.ENTRY_POINT, BASE_URL .. revision .. "/" .. PROJECT_PATH .. CONFIG.ENTRY_POINT)
  return chunk, err, revision
end
local reloadInFlight = false
local function reloadLatest(onFailure)
  if reloadInFlight then
    return false, "reload already in progress"
  end
  reloadInFlight = true
  local session = _G.ExodusLoaderSessionToken
  task.spawn(function()
    local ok, detail = xpcall(function()
      local chunk, prepareError, revision = prepareLoader()
      if not chunk then
        error(prepareError, 0)
      end
      if _G.ExodusLoaderSessionToken ~= session then
        return
      end
      _G.ExodusRequestedRevision = { revision = revision, automatic = false }
      chunk()
    end, function(err) return debug.traceback(tostring(err), 2) end)
    reloadInFlight = false
    if not ok then
      printRawError("Loader", detail)
      if type(onFailure) == "function" then
        task.defer(onFailure, detail)
      end
    end
  end)
  return true
end
local startToken = {}
local startupPerformed = false
local function startInternal()
  local wasStarted = Exodus.Started == true
  local requested = _G.ExodusRequestedRevision
  _G.ExodusRequestedRevision = nil
  local version, revisionError
  if type(requested) == "table" and validRevision(requested.revision) and BASE_URL then
    version = requested.revision
  else
    version, revisionError = resolveLatestRevision()
  end
  if not version then
    return false, "Loader", revisionError or "revisão atual indisponível"
  end
  local selected, selectionError = selectHub(version)
  if not selected then
    return false, "Loader", selectionError
  end
  local urls = buildURLs(version)
  local prepared, prepareModule, prepareError = loadModules(urls)
  if not prepared then
    return false, prepareModule, prepareError
  end
  local loaded, moduleName, loadError = loadModules(urls, prepared)
  if not loaded then
    return false, moduleName, loadError
  end
  local playerReady, playerError = waitForLocalPlayer(CONFIG.PLAYER_TIMEOUT)
  if not playerReady then
    return false, "Loader", playerError
  end
  if type(requested) == "table" and requested.automatic and Exodus.Context then
    local previous = Exodus.Context
    -- Release the start lock while waiting so an explicit loadstring can force a replacement.
    _G.ExodusLoaderStartToken = nil
    local safe = previous.updates.awaitSafe(function() return Exodus.Context == previous and previous.utils.getConfigValue("AutoExecute") == true end)
    if not safe or Exodus.Context ~= previous or _G.ExodusLoaderStartToken then
      return true
    end
    _G.ExodusLoaderStartToken = startToken
  end
  printStartup("Exodus: Initializing...")
  _G.ExodusShutdownReason = "restart"
  if not stopPreviousRuntime() then
    _G.ExodusShutdownReason = nil
    return false, "Loader", "failed to stop the previous session"
  end
  _G.ExodusShutdownReason = nil
  startupPerformed = true
  clearRegistry()
  for name, module in pairs(loaded) do
    Modules[name] = module
  end
  activeLoaded = loaded
  local uiReady, runtime = loaded.bootstrap.start(loaded, MODULE_ORDER, urls, selectedHub, {
    entryURL = function()
      return BASE_URL .. (CONFIG.BRANCH or (repositoryMetadata and repositoryMetadata.default_branch) or "main") .. "/" .. PROJECT_PATH .. CONFIG.ENTRY_POINT
    end,
    reload = reloadLatest,
    latest = resolveLatestRevision,
    prepare = function(revision) return loadModule("reload loader", CONFIG.ENTRY_POINT, BASE_URL .. revision .. "/" .. PROJECT_PATH .. CONFIG.ENTRY_POINT) end,
    report = printRawError,
  })
  local utils = loaded.utils
  Exodus.Runtime = runtime
  Exodus.Hub = table.clone(selectedHub)
  notifyPersistent(
    selectedHub.notification or ("Exodus Hub · " .. selectedHub.title .. " carregado."),
    "hub_loaded",
    "info",
    CONFIG.NOTIFICATIONS.HUB_LOADED_DURATION
  )
  Exodus.Context = loaded
  Exodus.UIReady = uiReady == true
  Exodus.UI = Modules.ui
  utils.setLifecyclePhase(uiReady == true and "ready" or "runtime_ready")
  Exodus.Started = true
  Exodus.Version = utils.version()
  Exodus.Revision = version
  _G.ExodusLastLoadedRevision = version
  if wasStarted then
    printStartup("Exodus: Reloaded.")
  else
    printStartup("Exodus: Initialized.")
  end
  return true
end

-- rollback
local function rollbackLoaded(loaded)
  if type(loaded) ~= "table" then
    return
  end
  if type(loaded.utils) == "table" and type(loaded.utils.stop) == "function" then
    cleanupCall("Session", loaded.utils.stop)
  end
end
local startLock = false
function Loader.start()
  if startLock or _G.ExodusLoaderStartToken then
    local message = "Inicialização já em andamento. Aguarde o carregamento atual."
    if type(warn) == "function" then
      warn("[Exodus] " .. message)
    else
      printStartup(message)
    end
    pcall(notifyPersistent, message, "startup_in_progress", "warning", CONFIG.NOTIFICATIONS.STARTUP_WARNING_DURATION)
    return true, nil, nil, "in_progress"
  end
  local ready, reason = validateExecutor()
  if not ready then
    return false, "Loader", reason
  end
  pcall(notifyPersistent, "Exodus · Loading...", "loading", "info", 0)
  startLock = true
  startupPerformed = false
  _G.ExodusLoaderStartToken = startToken
  Exodus.Modules = Modules
  _G.Exodus = Exodus
  _G.ExodusModules = Modules
  local ok, started, moduleName, startError = xpcall(startInternal, function(err) return debug.traceback(tostring(err), 2) end)
  pcall(clearPersistent, "loading")
  startLock = false
  if _G.ExodusLoaderStartToken == startToken then
    _G.ExodusLoaderStartToken = nil
  end
  if not ok then
    if startupPerformed then
      rollbackLoaded(activeLoaded)
      clearRegistry()
    end
    activeLoaded = nil
    return false, "Loader", started
  end
  if started ~= true then
    if startupPerformed then
      rollbackLoaded(activeLoaded)
      clearRegistry()
    end
    activeLoaded = nil
    return started, moduleName, startError
  end
  if startupPerformed then
    Exodus.Loader = Loader
    Modules.Loader = Loader
    _G.ExodusLoaderSessionToken = startToken
  end
  activeLoaded = nil
  return started, moduleName, startError
end
local function startSafely()
  local started, moduleName, startError, status = Loader.start()
  if status == "in_progress" then
    return nil
  end
  if started ~= true then
    moduleName = moduleName or "Loader"
    startError = startError or started
    local entry = MODULE_BY_NAME[moduleName]
    printRawError(moduleName, startError, entry and entry.path or CONFIG.ENTRY_POINT)
    notifyCritical(moduleName)
    Loader.lastError = startError
    Loader.lastErrorModule = moduleName
    Exodus.StartError = startError
    Exodus.StartErrorModule = moduleName
    error(("%s: %s"):format(tostring(moduleName), tostring(startError)), 2)
  end
  Loader.lastError = nil
  Loader.lastErrorModule = nil
  Exodus.StartError = nil
  Exodus.StartErrorModule = nil
  return true
end
local started = startSafely()
if started ~= nil then
  Exodus.Started = started == true
end

return Loader
