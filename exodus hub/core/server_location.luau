-- [[ server location sources ]]
--!optimize 2
-- @modules serverlocation

local Location = {}
local scope, result, failure
-- Region codes identify the datacenter area, not precise street coordinates.
local regions = {
  AMS = { "Países Baixos", "Amsterdã" },
  BOM = { "Índia", "Mumbai" },
  CDG = { "França", "Paris" },
  DFW = { "Estados Unidos", "Dallas" },
  FRA = { "Alemanha", "Frankfurt" },
  GRU = { "Brasil", "São Paulo" },
  HKG = { "Hong Kong", "Hong Kong" },
  IAD = { "Estados Unidos", "Ashburn" },
  LAX = { "Estados Unidos", "Los Angeles" },
  LHR = { "Reino Unido", "Londres" },
  MIA = { "Estados Unidos", "Miami" },
  NRT = { "Japão", "Tóquio" },
  ORD = { "Estados Unidos", "Chicago" },
  SEA = { "Estados Unidos", "Seattle" },
  SIN = { "Singapura", "Singapura" },
  SJC = { "Estados Unidos", "San Jose" },
  SYD = { "Austrália", "Sydney" },
  WAW = { "Polônia", "Varsóvia" },
}
local function text(value)
  if type(value) == "string" and value:match("%S") then
    return value
  end
  return nil
end
local function publicIP(value)
  if type(value) ~= "string" then
    return nil
  end
  local ip = value:match("^(%d+%.%d+%.%d+%.%d+)[|:]?%d*$")
  if not ip then
    return nil
  end
  local octets = {}
  for part in ip:gmatch("%d+") do
    local n = tonumber(part)
    if not n or n > 255 then
      return nil
    end
    octets[#octets + 1] = n
  end
  local a, b = octets[1], octets[2]
  if
    a == 0
    or a == 10
    or a == 127
    or a >= 224
    or (a == 100 and b >= 64 and b <= 127)
    or (a == 169 and b == 254)
    or (a == 172 and b >= 16 and b <= 31)
    or (a == 192 and b == 168)
    or (a == 192 and b == 0)
    or (a == 198 and (b == 18 or b == 19 or b == 51))
    or (a == 203 and b == 0)
  then
    return nil
  end
  return ip
end
local function attribute(object, name)
  local ok, value = pcall(function()
    local current = object:GetAttribute(name)
    if current ~= nil then
      return current
    end
    local child = object:FindFirstChild(name)
    return child and child:IsA("StringValue") and child.Value or nil
  end)
  return ok and text(value) or nil
end
function Location.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  return true
end
function Location.setup(deps)
  Location.teardown()
  scope, result, failure = deps.Lifetime.scope(), {}, nil
  local owner = scope
  local environment = type(getgenv) == "function" and getgenv() or _G
  local request = environment.request or environment.http_request or (environment.syn and environment.syn.request)
  local function fetch(url)
    local raw
    if type(request) == "function" then
      local response = request({ Url = url, Method = "GET", Timeout = 5 })
      assert(type(response) == "table" and (response.StatusCode == nil or response.StatusCode == 200), "HTTP lookup failed")
      raw = response.Body
    else
      raw = game:HttpGet(url)
    end
    return game:GetService("HttpService"):JSONDecode(raw)
  end
  local resolving, peer = false, nil
  local samples, localCountry = {}, nil
  local function resolve(value)
    local ip = publicIP(value)
    if not owner.alive or not ip or resolving or (result.country and result.city) then
      return
    end
    resolving, peer = true, ip
    -- Always pass the verified peer address. An empty URL would locate the user.
    for _, url in ipairs({ "https://ipwho.is/" .. ip, "https://ipapi.co/" .. ip .. "/json/" }) do
      task.spawn(function()
        if not owner.alive then
          return
        end
        local ok, data = pcall(fetch, url)
        if not owner.alive or not ok or type(data) ~= "table" or data.ip ~= ip or data.success == false or data.error then
          return
        end
        if result.estimated then
          result = {}
        end
        result.source = "Geolocalização do endereço do servidor"
        result.country = result.country or text(data.country_name) or text(data.country)
        result.city = result.city or text(data.city)
        if result.country and result.city then
          failure = nil
        end
      end)
    end
    task.delay(10, function()
      if owner.alive and not (result.country and result.city) then
        resolving = false
      end
    end)
  end
  local function readMetadata()
    local ok, code = pcall(function() return game.ServerRegion end)
    local native = ok and text(code) and regions[string.upper(code)]
    if native then
      result = { country = native[1], city = native[2], source = "Região publicada pelo servidor" }
    end
    for _, object in ipairs({ game, game:GetService("Workspace"), game:GetService("ReplicatedStorage") }) do
      if result.estimated and (attribute(object, "ServerCountry") or attribute(object, "ServerRegion")) then
        result = {}
      end
      result.country = result.country or attribute(object, "ServerCountry")
      result.city = result.city or attribute(object, "ServerCity")
      local region = attribute(object, "ServerRegion")
      local mapped = region and regions[string.upper(region)]
      if mapped then
        result.country, result.city = result.country or mapped[1], result.city or mapped[2]
      end
      if result.country and result.city then
        failure = nil
      end
    end
  end
  pcall(readMetadata)
  task.spawn(function()
    if not owner.alive then
      return
    end
    pcall(function()
      local network = game:GetService("NetworkClient")
      owner.connect(network.ConnectionAccepted, function(peer) resolve(peer) end)
    end)
    -- Logs are useful only when they identify this exact session. Never use an
    -- arbitrary IP from output, an old join, player country, or a join-ticket API.
    pcall(function()
      local logs = game:GetService("LogService"):GetLogHistory()
      local current = false
      for _, record in ipairs(logs) do
        local message = record.message or ""
        local job = message:match("! Joining game '([^']*)'")
        if job then
          current = job == game.JobId
        end
        if current then
          local address = message:match("UDMUX Address = (%d+%.%d+%.%d+%.%d+)")
            or message:match("Connecting to UDMUX server (%d+%.%d+%.%d+%.%d+)")
            or message:match("Connection accepted from (%d+%.%d+%.%d+%.%d+)")
          if address then
            resolve(address)
          end
        end
      end
    end)
  end)
  for _, service in ipairs({ "Workspace", "ReplicatedStorage" }) do
    pcall(function()
      local object = game:GetService(service)
      for _, name in ipairs({ "ServerCountry", "ServerCity", "ServerRegion" }) do
        owner.connect(object:GetAttributeChangedSignal(name), readMetadata)
      end
    end)
  end
  -- Client geolocation is only a fallback country hint, never server-city evidence.
  local function estimate()
    if not owner.alive or (result.country and not result.estimated) then
      return
    end
    local stable = #samples >= 20
    local low, high = math.huge, 0
    for _, ping in ipairs(samples) do
      low, high = math.min(low, ping), math.max(high, ping)
    end
    stable = stable and high <= 60 and high - low <= 15
    if stable and localCountry then
      result = { country = localCountry, estimated = true, source = "Estimativa: país da conexão e ping baixo estável" }
      failure = nil
    elseif result.estimated then
      result = {}
    end
  end
  pcall(function()
    local elapsed = 0
    owner.connect(game:GetService("RunService").Heartbeat, function(dt)
      elapsed += dt
      if elapsed < 1 then
        return
      end
      elapsed = 0
      local ok, ping = pcall(function() return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
      if ok and type(ping) == "number" and ping == ping and ping > 0 and ping < math.huge then
        samples[#samples + 1] = ping
        if #samples > 20 then
          table.remove(samples, 1)
        end
      else
        table.clear(samples)
      end
      estimate()
    end)
  end)
  task.delay(8, function()
    if owner.alive and not (result.country and result.city) then
      failure = "Localização ainda não confirmada."
      task.spawn(function()
        for _, url in ipairs({ "https://ipwho.is/", "https://ipapi.co/json/" }) do
          if not owner.alive then
            return
          end
          local ok, data = pcall(fetch, url)
          if owner.alive and ok and type(data) == "table" and data.success ~= false and not data.error then
            localCountry = text(data.country_name) or text(data.country)
            if localCountry then
              estimate()
              break
            end
          end
        end
      end)
    end
  end)
  local function retryMetadata()
    if not owner.alive then
      return
    end
    pcall(readMetadata)
    if peer then
      resolve(peer)
    end
    task.delay(30, retryMetadata)
  end
  task.delay(30, retryMetadata)
  return true
end
function Location.snapshot() return table.clone(result or {}), failure end
Location.__contract = {
  access = { methods = { snapshot = "internal.read" } },
  provides = { "setup", "teardown", "snapshot" },
  requires = { Lifetime = "lifetime" },
  requiresMethods = { Lifetime = { "scope" } },
}
return Location
