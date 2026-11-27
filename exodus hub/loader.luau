-- [[ loader ]]
--!optimize 2

-- configuration
local CONFIG = {
  USER_ID = 222319587,
  REPOSITORY_ID = 1334849119,
  REPOSITORY_NAME = "Repp35/Exodus-Hub",
  DEFAULT_BRANCH = "main",
  BRANCH = false,
  REVISION = false,
  ENTRY_POINT = "loader.luau",
  MAX_ATTEMPTS = 1,
  RETRY_DELAYS = { 0.25, 0.75, 1.5 },
  RATE_LIMIT_DEFAULT_DELAY = 5,
  MAX_AUTO_RETRY_DELAY = 60,
  PLAYER_TIMEOUT = 10,
  CACHE_WAIT_TIMEOUT = 60,
  BYPASS_IMMUTABLE_CACHE = false,
  DEBUG = false,
  DOWNLOAD_WORKERS = 1,
  REQUEST_INTERVAL = 0,
  REQUEST_TIMEOUT = 5,
  MAX_PENDING_REQUESTS = 3,
  DOWNLOAD_TIMEOUT = 5,
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
  ACCESS_PATH = "hubs/access.luau",
  CATALOG_PATH = "hubs/catalog.luau",
  MANIFEST_PATH = "core/catalog.luau",
  BUNDLE_PATH = "dist/runtime.json",
  NOTIFICATIONS = {
    DEFAULT_DURATION = 2.5,
    STARTUP_WARNING_DURATION = 2.5,
    NAVIGATION_DURATION = 5,
    HUB_LOADED_DURATION = 5,
    DISPLAY_ORDER = 2147483647,
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
-- generated-start
local Appearance = (function()
  --!optimize 2

  local Appearance = {}
  function Appearance.setup() return true end
  function Appearance.borderColor(background, light)
    local hue, saturation, value = background:ToHSV()
    if saturation < 0.1 then
      hue, saturation = 0.69, 0.50
    end
    saturation = math.clamp(saturation, 0.45, 0.80)
    local brightness = value > 0.72 and value * 0.70 or math.clamp(value + 0.14, 0.25, 0.55)
    return Color3.fromHSV(hue, saturation, brightness)
  end
  function Appearance.interactionColor(background, pressed)
    local hue, saturation, value = Appearance.borderColor(background):ToHSV()
    return Color3.fromHSV(hue, saturation, math.min(0.72, value + (pressed and 0.09 or 0.05)))
  end
  function Appearance.borderGradient(background, strength)
    local hue, saturation = background:ToHSV()
    local color = strength and strength > 0 and Appearance.interactionColor(background, strength > 1) or Appearance.borderColor(background)
    local _, tint, value = color:ToHSV()
    if saturation < 0.1 then
      hue = 0.69
    end
    local first = (hue - 0.025) % 1
    local last = (hue + 0.025) % 1
    return ColorSequence.new(Color3.fromHSV(first, tint, value), Color3.fromHSV(last, tint, value))
  end
  local function instance(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties) do
      object[key] = value
    end
    object.Parent = parent
    return object
  end
  local function palette(kind)
    if kind == "critical" then
      return Color3.fromRGB(153, 27, 27)
    end
    if kind == "success" then
      return Color3.fromRGB(20, 92, 58)
    end
    if kind == "warning" then
      return Color3.fromRGB(100, 67, 18)
    end
    return Color3.fromRGB(45, 55, 130)
  end
  function Appearance.notification(parent, name)
    local card = instance("CanvasGroup", {
      Name = name,
      AnchorPoint = Vector2.new(0.5, 1),
      Position = UDim2.new(0.5, 0, 1, 18),
      Size = UDim2.fromOffset(80, 26),
      BackgroundTransparency = 0.12,
      BorderSizePixel = 0,
      GroupTransparency = 1,
      ClipsDescendants = true,
      ZIndex = 100,
    }, parent)
    instance("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
    local outline = instance("Frame", {
      Name = "Outline",
      Size = UDim2.new(1, -2, 1, -2),
      Position = UDim2.fromOffset(1, 1),
      BackgroundTransparency = 1,
      BorderSizePixel = 0,
      ZIndex = 102,
    }, card)
    instance("UICorner", { CornerRadius = UDim.new(0, 9) }, outline)
    instance("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, outline)
    local content = instance("ScrollingFrame", {
      Name = "Content",
      Size = UDim2.new(1, -20, 1, -12),
      Position = UDim2.fromOffset(10, 6),
      BackgroundTransparency = 1,
      BorderSizePixel = 0,
      CanvasSize = UDim2.new(),
      ScrollBarThickness = 0,
      ScrollingDirection = Enum.ScrollingDirection.Y,
      Active = true,
      ClipsDescendants = true,
      ZIndex = 101,
    }, card)
    instance("TextLabel", {
      Name = "Message",
      BackgroundTransparency = 1,
      BorderSizePixel = 0,
      Size = UDim2.new(1, 0, 1, 0),
      Text = "",
      TextColor3 = Color3.new(1, 1, 1),
      TextSize = 11,
      Font = Enum.Font.GothamMedium,
      TextWrapped = true,
      TextTruncate = Enum.TextTruncate.None,
      TextXAlignment = Enum.TextXAlignment.Center,
      TextYAlignment = Enum.TextYAlignment.Center,
      RichText = false,
      ZIndex = 101,
    }, content)
    return card
  end
  function Appearance.updateNotification(card, message, kind, viewport)
    local content = card:FindFirstChild("Content")
    assert(content and content:IsA("ScrollingFrame"), "Unsupported notification surface")
    local label = content:FindFirstChild("Message")
    local maxWidth = math.max(24, math.min(280, viewport.X - 24))
    local padding = math.min(10, math.max(2, (maxWidth - 4) / 4))
    local measure = game:GetService("TextService")
    local value = tostring(message)
    local function bounds(width) return measure:GetTextSize(value, 11, Enum.Font.GothamMedium, Vector2.new(math.max(1, width), 100000)) end
    local size = bounds(maxWidth - padding * 2)
    local width = math.min(maxWidth, math.max(math.min(80, maxWidth), math.ceil(size.X) + padding * 2 + 2))
    size = bounds(width - padding * 2)
    local maxHeight = math.max(26, viewport.Y - 48)
    local height = math.min(maxHeight, math.max(26, math.ceil(size.Y) + 14))
    local overflow = size.Y + 12 > height
    if overflow then
      size = bounds(width - padding * 2 - 4)
    end
    card.Size = UDim2.fromOffset(width, height)
    card.BackgroundColor3 = palette(kind)
    card.BackgroundTransparency = 0.12
    local outline = card:FindFirstChild("Outline")
    local line = outline:FindFirstChildOfClass("UIStroke")
    line.Color = Color3.new(1, 1, 1)
    local gradient = line:FindFirstChildOfClass("UIGradient") or instance("UIGradient", { Rotation = 20 }, line)
    gradient.Color = Appearance.borderGradient(card.BackgroundColor3)
    content.Position = UDim2.fromOffset(padding, 6)
    content.Size = UDim2.new(1, -padding * 2, 1, -12)
    content.ScrollingEnabled, content.ScrollBarThickness = overflow, overflow and 2 or 0
    content.ScrollBarImageColor3 = Color3.new(1, 1, 1)
    content.CanvasSize = UDim2.fromOffset(0, math.ceil(size.Y) + 2)
    content.CanvasPosition = Vector2.new(0, 0)
    label.Text = value
    label.Size = UDim2.new(1, overflow and -4 or 0, 0, math.max(height - 12, math.ceil(size.Y) + 2))
    return card
  end
  Appearance.__contract = { provides = { "setup", "borderColor", "interactionColor", "borderGradient", "notification", "updateNotification" }, requires = {} }
  return Appearance
end)()
-- generated-end
local function fallbackNotification(message, key, kind, duration)
  local player = game:GetService("Players").LocalPlayer
  local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
  if not playerGui then
    return
  end
  local gui = playerGui:FindFirstChild("ExodusPersistentNotifications")
  if not gui then
    gui = Instance.new("ScreenGui")
    gui.Name, gui.DisplayOrder = "ExodusPersistentNotifications", CONFIG.NOTIFICATIONS.DISPLAY_ORDER
    gui.ResetOnSpawn, gui.IgnoreGuiInset = false, true
    gui.ZIndexBehavior, gui.Parent = Enum.ZIndexBehavior.Global, playerGui
  end
  local layer = gui:FindFirstChild("NotificationLayer")
  if not layer then
    layer = Instance.new("Frame")
    layer.Name, layer.Size, layer.BackgroundTransparency, layer.Parent = "NotificationLayer", UDim2.fromScale(1, 1), 1, gui
  end
  local safeKey = tostring(key or "critical"):gsub("[^%w_%-]", "_")
  local card = layer:FindFirstChild("Notification_" .. safeKey)
  if card and not card:FindFirstChild("Content") then
    card:Destroy()
    card = nil
  end
  if not card then
    card = Appearance.notification(layer, "Notification_" .. safeKey)
    card:SetAttribute("ExodusNotificationKey", safeKey)
  end
  local camera = workspace.CurrentCamera
  Appearance.updateNotification(card, message, kind, camera and camera.ViewportSize or Vector2.new(1920, 1080))
  if duration == nil and key ~= "dumper" then
    duration = CONFIG.NOTIFICATIONS.DEFAULT_DURATION
  end
  card.GroupTransparency, card.Visible = 1, true
  local offset = 24
  for _, item in ipairs(layer:GetChildren()) do
    if item:IsA("CanvasGroup") and item:GetAttribute("ExodusNotificationKey") then
      game
        :GetService("TweenService")
        :Create(item, TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
          GroupTransparency = 0,
          Position = UDim2.new(0.5, 0, 1, -offset),
        })
        :Play()
      offset += item.Size.Y.Offset + 8
    end
  end
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
    local ok, tween = pcall(clear, key)
    if ok then
      return tween
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
    local tween = game:GetService("TweenService"):Create(card, TweenInfo.new(0.3), { GroupTransparency = 1 })
    tween:Play()
    tween.Completed:Once(function(status)
      if status == Enum.PlaybackState.Completed and card.Parent and card:GetAttribute("ExodusNotificationGeneration") == generation then
        card:Destroy()
      end
    end)
    return tween
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
  local candidates, seen = {}, {}
  local function add(candidate)
    if type(candidate) == "function" and not seen[candidate] then
      seen[candidate] = true
      candidates[#candidates + 1] = candidate
    end
  end
  add(environment.request)
  add(environment.http_request)
  for _, name in ipairs({ "syn", "fluxus", "http" }) do
    local api = environment[name]
    if type(api) == "table" then
      add(api.request)
    end
  end
  add(function(options) return { StatusCode = 200, Body = game:HttpGet(options.Url) } end)
  add(function(options) return { StatusCode = 200, Body = game:HttpGetAsync(options.Url) } end)
  add(function(options) return { StatusCode = 200, Body = HttpService:GetAsync(options.Url) } end)
  local first = 1
  local function advance() first = first % #candidates + 1 end
  return function(options)
    local reason = "Nenhum transporte HTTP respondeu"
    local start = first
    for offset = 0, #candidates - 1 do
      local index = (start + offset - 1) % #candidates + 1
      local ok, response = pcall(candidates[index], options)
      if ok and type(response) == "table" then
        local code = tonumber(response.StatusCode or response.status_code)
        local body = response.Body or response.body or response.ResponseBody
        if code and (code < 200 or code >= 300) or type(body) == "string" and body ~= "" then
          first = index
          if not code then
            response.StatusCode = 200
          end
          return response
        end
      end
      reason = tostring(response)
      if not ok then
        local code = tonumber(reason:match("[Hh][Tt][Tt][Pp]%s*:?%s*(%d%d%d)"))
        if code then
          return { StatusCode = code, Body = reason }
        end
      end
    end
    error(reason, 0)
  end,
    advance
end
local requestFunction, advanceTransport = getRequestFunction()
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
if type(requestState.cooldowns) ~= "table" then
  requestState.cooldowns = {}
  if type(requestState.retryAt) == "number" then
    requestState.cooldowns["api.github.com"] = requestState.retryAt
  end
end
_G.ExodusRequestState = requestState
local function host(url) return url:match("^https://([^/]+)") or "" end
local function blocked(url)
  local deadline = requestState.cooldowns[host(url)] or 0
  if deadline > os.time() then
    requestState.retryAt = deadline
    return { rateLimited = true, retryAfter = deadline - os.time() }
  end
end
local function requestOnce(url, headers)
  if not requestFunction then
    return nil, "Nenhum serviço HTTP disponível"
  end
  if type(task) == "table" and type(task.wait) == "function" then
    if requestState.pending >= CONFIG.MAX_PENDING_REQUESTS then
      return nil, "Transportes HTTP ocupados"
    end
    local queueDeadline = os.clock() + CONFIG.REQUEST_TIMEOUT
    while true do
      local cooldown = blocked(url)
      if cooldown then
        return nil, "Aguardando limite HTTP", cooldown
      end
      local now = os.clock()
      if now >= queueDeadline then
        return nil, "Tempo limite ao esperar a fila HTTP"
      end
      local wait = (requestState.nextRequestAt or 0) - now
      if wait <= 0 and requestState.pending < CONFIG.MAX_PENDING_REQUESTS then
        requestState.nextRequestAt = now + CONFIG.REQUEST_INTERVAL
        break
      end
      task.wait(math.max(0.05, math.min(wait > 0 and wait or 0.1, 1)))
    end
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
      advanceTransport()
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
local function requestSingle(url, headers)
  if type(url) ~= "string" or url == "" then
    return nil, "URL inválida"
  end
  if not requestFunction then
    return nil, "Nenhum serviço HTTP disponível"
  end
  local cooldown = blocked(url)
  if cooldown then
    return nil, "Aguardando limite HTTP", cooldown
  end
  local lastError, lastMeta
  for attempt = 1, CONFIG.MAX_ATTEMPTS do
    local body, err, meta = requestOnce(url, headers)
    if body then
      requestState.retryAt = nil
      return body
    end
    lastError, lastMeta = err, meta
    if meta and meta.rateLimited then
      local key = host(url)
      requestState.cooldowns[key] = math.max(requestState.cooldowns[key] or 0, os.time() + math.max(1, meta.retryAfter or CONFIG.RATE_LIMIT_DEFAULT_DELAY))
      requestState.retryAt = requestState.cooldowns[key]
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
local function validSource(source, path)
  if type(source) ~= "string" or source == "" then
    return false
  end
  if path:match("%.json$") then
    local ok, data = pcall(HttpService.JSONDecode, HttpService, source)
    return ok and type(data) == "table" and data.version == 1 and type(data.sources) == "table"
  end
  return type(loadstring) == "function" and loadstring(source, path) ~= nil
end
local function githubPayload(body)
  local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
  if not ok or type(data) ~= "table" or data.encoding ~= "base64" or type(data.content) ~= "string" then
    return nil
  end
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local bytes, value, bits = {}, 0, 0
  for char in data.content:gmatch(".") do
    if char == "=" then
      break
    end
    if not char:match("%s") then
      local position = alphabet:find(char, 1, true)
      if not position then
        return nil
      end
      value, bits = value * 64 + position - 1, bits + 6
      if bits >= 8 then
        bits -= 8
        local divisor = 2 ^ bits
        bytes[#bytes + 1] = string.char(math.floor(value / divisor))
        value %= divisor
      end
    end
  end
  return table.concat(bytes), data.sha
end
local function request(url, headers)
  local owner, repo, revision, path = url:match("^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([%x]+)/([^?]+)")
  local pinned = owner and validRevision(revision)
  local body, reason, meta = requestSingle(url, headers)
  if body and (not pinned or validSource(body, path)) then
    return body
  end
  if not pinned then
    return nil, reason, meta
  end
  if meta and meta.rateLimited and (meta.retryAfter or 0) <= 5 then
    return nil, reason, meta
  end
  reason = reason or "Resposta inválida da origem"
  pcall(notifyPersistent, "Exodus · Falha na origem. Tentando fontes alternativas…", "loader_transport", "critical", 5)
  local prefix = owner .. "/" .. repo
  local suffix = prefix .. "@" .. revision .. "/" .. path
  local mirrors = {
    { url = "https://cdn.jsdelivr.net/gh/" .. suffix },
    { url = "https://rawcdn.githack.com/" .. prefix .. "/" .. revision .. "/" .. path },
    { url = "https://cdn.statically.io/gh/" .. suffix },
    {
      url = "https://api.github.com/repos/" .. prefix .. "/contents/" .. path .. "?ref=" .. revision,
      headers = { Accept = "application/vnd.github.raw+json", ["User-Agent"] = "Exodus-Hub-Loader" },
    },
    {
      url = "https://api.github.com/repos/" .. prefix .. "/contents/" .. path .. "?ref=" .. revision,
      headers = { Accept = "application/vnd.github.object+json" },
      json = true,
    },
    { url = "https://raw.githack.com/" .. prefix .. "/" .. revision .. "/" .. path },
    { url = "https://github.com/" .. prefix .. "/raw/" .. revision .. "/" .. path },
    { url = "https://fastly.jsdelivr.net/gh/" .. suffix },
    { url = "https://gcore.jsdelivr.net/gh/" .. suffix },
    { url = "https://testingcf.jsdelivr.net/gh/" .. suffix },
    { url = "https://quantil.jsdelivr.net/gh/" .. suffix },
    { url = "https://api.github.com/repos/" .. prefix .. "/git/blobs/", blob = true, headers = { Accept = "application/vnd.github.raw+json" } },
    { url = "https://api.github.com/repos/" .. prefix .. "/git/blobs/", blob = true, json = true, headers = { Accept = "application/vnd.github+json" } },
  }
  local preferred = requestState.preferredSource
  for index, mirror in ipairs(mirrors) do
    if host(mirror.url) == preferred then
      mirrors[1], mirrors[index] = mirror, mirrors[1]
      break
    end
  end
  local deadline = os.clock() + CONFIG.REQUEST_TIMEOUT
  for _, mirror in ipairs(mirrors) do
    if os.clock() >= deadline then
      break
    end
    local target = mirror.url
    if mirror.blob then
      requestState.blobs = type(requestState.blobs) == "table" and requestState.blobs or {}
      local blob = requestState.blobs[url]
      if not validRevision(blob) and not blocked(target) then
        local raw =
          requestSingle("https://api.github.com/repos/" .. prefix .. "/git/trees/" .. revision .. "?recursive=1", { Accept = "application/vnd.github+json" })
        if raw then
          local ok, tree = pcall(HttpService.JSONDecode, HttpService, raw)
          if ok and type(tree) == "table" and type(tree.tree) == "table" then
            local decodedPath = path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
            for _, entry in ipairs(tree.tree) do
              if entry.type == "blob" and entry.path == decodedPath and validRevision(entry.sha) then
                blob = entry.sha
                requestState.blobs[url] = blob
                break
              end
            end
          end
        end
      end
      target = validRevision(blob) and (target .. blob) or nil
    end
    local source = target and requestSingle(target, mirror.headers)
    if source and mirror.json then
      local decoded, blob = githubPayload(source)
      source = decoded
      if validRevision(blob) then
        requestState.blobs = type(requestState.blobs) == "table" and requestState.blobs or {}
        requestState.blobs[url] = blob
      end
    end
    if source and validSource(source, path) then
      requestState.preferredSource = host(mirror.url)
      pcall(clearPersistent, "loader_transport")
      return source
    end
  end
  requestState.retryAt = requestState.cooldowns[host(url)]
  return nil, reason .. "; fontes alternativas indisponíveis", meta
end

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
local function resolveGitRevision()
  local repo = repositoryMetadata or { full_name = CONFIG.REPOSITORY_NAME, default_branch = CONFIG.DEFAULT_BRANCH }
  local branch = CONFIG.BRANCH or repo.default_branch
  local body, reason = requestSingle("https://github.com/" .. repo.full_name .. ".git/info/refs?service=git-upload-pack", { ["Git-Protocol"] = "version=0" })
  if not body then
    local cached = _G.ExodusLastLoadedRevision
    if validRevision(cached) then
      BASE_URL = CONFIG.RAW_BASE_URL .. repo.full_name .. "/"
      _G.ExodusRepositoryBaseURL = BASE_URL
      return cached
    end
    return nil, reason
  end
  local cursor = 1
  while cursor + 3 <= #body do
    local length = tonumber(body:sub(cursor, cursor + 3), 16)
    if not length then
      break
    end
    if length == 0 then
      cursor += 4
    elseif length < 4 or cursor + length - 1 > #body then
      break
    else
      local packet = body:sub(cursor + 4, cursor + length - 1)
      local revision, ref = packet:match("^([%x]+) ([^%z\n]+)")
      if validRevision(revision) and ref == "refs/heads/" .. branch then
        BASE_URL = CONFIG.RAW_BASE_URL .. repo.full_name .. "/"
        _G.ExodusRepositoryBaseURL = BASE_URL
        return revision
      end
      cursor += length
    end
  end
  return nil, "Não foi possível resolver a revisão pelo protocolo Git"
end
local function resolveLatestRevision()
  local repositoryURL = CONFIG.REPOSITORY_API .. tostring(CONFIG.REPOSITORY_ID)
  local headers = CONFIG.API_HEADERS
  local repo = repositoryMetadata
  if not repo then
    local metadata, metadataError, metadataMeta = request(repositoryURL .. "?" .. CONFIG.CACHE_QUERY_KEY .. "=" .. cacheBuster(), headers)
    if not metadata then
      if not metadataMeta or not metadataMeta.rateLimited or metadataMeta.retryAfter > 5 then
        pcall(notifyPersistent, "Exodus · API limitada. Consultando revisão por Git…", "loader_transport", "critical", 5)
        return resolveGitRevision()
      end
      return nil, metadataError
    end
    local decoded
    decoded, repo = pcall(HttpService.JSONDecode, HttpService, metadata)
    if not decoded or type(repo) ~= "table" or type(repo.full_name) ~= "string" or not repo.full_name:match("^[%w_.%-]+/[%w_.%-]+$") then
      return resolveGitRevision()
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
    local body, requestError, requestMeta = request(headURL .. "?" .. CONFIG.CACHE_QUERY_KEY .. "=" .. cacheBuster(), headers)
    if not body then
      if not requestMeta or not requestMeta.rateLimited or requestMeta.retryAfter > 5 then
        return resolveGitRevision()
      end
      return nil, requestError
    end
    local ok, document = pcall(HttpService.JSONDecode, HttpService, body)
    revision = ok and type(document) == "table" and type(document.object) == "table" and document.object.sha
    if not validRevision(revision) then
      return resolveGitRevision()
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
local sourceBundle
local function bundledSource(path, url)
  local root = url:sub(1, #url - #path)
  if sourceBundle and sourceBundle.root == root then
    return sourceBundle.sources[path]
  end
  local cached = sourceCache.bundle
  if cached and cached.root == root then
    sourceBundle = cached
    return cached.sources[path]
  end
  local body, reason = request(root .. CONFIG.BUNDLE_PATH)
  if not body then
    return nil, reason
  end
  local ok, bundle = pcall(HttpService.JSONDecode, HttpService, body)
  if not ok or type(bundle) ~= "table" or bundle.version ~= 1 or type(bundle.sources) ~= "table" then
    return nil, "Pacote de módulos inválido"
  end
  for name, source in pairs(bundle.sources) do
    if type(name) ~= "string" or type(source) ~= "string" then
      return nil, "Fonte inválida no pacote"
    end
  end
  sourceBundle = { root = root, sources = bundle.sources }
  sourceCache.bundle = sourceBundle
  return bundle.sources[path], "Módulo ausente no pacote: " .. path
end
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
      if relativePath == CONFIG.ENTRY_POINT then
        source, fetchError = request(downloadURL, headers)
      else
        source, fetchError = bundledSource(relativePath, url)
      end
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
  local accessChunk, accessError = loadModule("hub access", CONFIG.ACCESS_PATH, root .. CONFIG.ACCESS_PATH)
  if not accessChunk then
    return false, accessError
  end
  local player = game:GetService("Players").LocalPlayer
  local selectionError
  selectedHub, selectionError = registry.resolve(catalog, game.PlaceId, game.GameId, {
    userId = player and player.UserId,
    username = player and player.Name,
  }, execute("hub access", accessChunk))
  if not selectedHub then
    return false, selectionError
  end
  local manifestChunk, manifestError = loadModule("shared manifest", CONFIG.MANIFEST_PATH, root .. CONFIG.MANIFEST_PATH)
  if not manifestChunk then
    return false, manifestError
  end
  MODULE_MANIFEST = registry.manifest(execute("shared manifest", manifestChunk), selectedHub)
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
            deadline = os.clock() + CONFIG.DOWNLOAD_TIMEOUT
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
  local linker = execute("modulelinker", results.modulelinker.chunk)
  results.modulelinker.module = linker
  local permissions = results.permissions and execute("permissions", results.permissions.chunk) or linker
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
  MODULE_ORDER = loaded.modulelinker.order(MODULE_MANIFEST, loaded)
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
local reloadInFlight, reloadGeneration = false, 0
local function reloadLatest(onFailure)
  if reloadInFlight then
    return false, "reload already in progress"
  end
  reloadInFlight = true
  reloadGeneration += 1
  local generation = reloadGeneration
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
      local delay = requestState.retryAt and requestState.retryAt > os.time() and (requestState.retryAt - os.time()) or 10
      if delay > CONFIG.MAX_AUTO_RETRY_DELAY then
        pcall(
          notifyPersistent,
          ("Exodus · Limite HTTP: espera de %ds. Atualização cancelada; execute novamente mais tarde."):format(math.ceil(delay)),
          "loader_retry",
          "critical",
          10
        )
        return
      end
      if delay > 5 then
        pcall(notifyPersistent, ("Exodus · Erro na atualização. Nova tentativa em %ds."):format(math.ceil(delay)), "loader_retry", "critical", 0)
      end
      if type(onFailure) == "function" then
        task.defer(onFailure, detail)
      end
      task.delay(delay, function()
        if generation == reloadGeneration and _G.ExodusLoaderSessionToken == session and Exodus.Context and Exodus.Context.utils.isActive() then
          reloadLatest(onFailure)
        end
      end)
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
  local playerReady, playerError = waitForLocalPlayer(CONFIG.PLAYER_TIMEOUT)
  if not playerReady then
    return false, "Loader", playerError
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
  if type(requested) == "table" and requested.automatic and Exodus.Context then
    local previous = Exodus.Context
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
    revision = version,
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
  local loadingExit = clearPersistent("loading")
  if loadingExit then
    loadingExit.Completed:Wait()
  end
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
  pcall(notifyPersistent, "Exodus · Carregando…", "loading", "info", 0)
  startLock = true
  startupPerformed = false
  _G.ExodusLoaderStartToken = startToken
  Exodus.Modules = Modules
  _G.Exodus = Exodus
  _G.ExodusModules = Modules
  local ok, started, moduleName, startError = xpcall(startInternal, function(err) return debug.traceback(tostring(err), 2) end)
  if not ok or started ~= true then
    pcall(clearPersistent, "loading")
  end
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
local retryCount = 0
local recoveryToken = {}
local function startSafely()
  local started, moduleName, startError, status = Loader.start()
  if status == "in_progress" then
    return nil
  end
  _G.ExodusLoaderRecoveryToken = recoveryToken
  if started ~= true then
    moduleName = moduleName or "Loader"
    startError = startError or started
    local entry = MODULE_BY_NAME[moduleName]
    Loader.lastError = startError
    Loader.lastErrorModule = moduleName
    Exodus.StartError = startError
    Exodus.StartErrorModule = moduleName
    retryCount += 1
    local delay = requestState.retryAt and requestState.retryAt > os.time() and (requestState.retryAt - os.time())
      or math.min(60, 5 * 2 ^ math.min(retryCount - 1, 4))
    if delay > 5 then
      printRawError(moduleName, startError, entry and entry.path or CONFIG.ENTRY_POINT)
    end
    if delay > CONFIG.MAX_AUTO_RETRY_DELAY then
      _G.ExodusLoaderRecoveryToken = nil
      pcall(
        notifyPersistent,
        ("Exodus · Limite HTTP: espera de %ds. Carga cancelada; execute novamente mais tarde."):format(math.ceil(delay)),
        "loader_retry",
        "critical",
        10
      )
      return nil
    end
    if delay > 5 then
      pcall(
        notifyPersistent,
        ("Exodus · Erro: %s. Nova tentativa em %ds."):format(tostring(startError):match("[^\n]+") or tostring(startError), math.ceil(delay)),
        "loader_retry",
        "critical",
        0
      )
    else
      pcall(clearPersistent, "loader_retry")
    end
    task.delay(delay, function()
      if _G.ExodusLoaderRecoveryToken == recoveryToken and not _G.ExodusLoaderStartToken then
        startSafely()
      end
    end)
    return nil
  end
  retryCount = 0
  pcall(clearPersistent, "loader_retry")
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
