-- [[ server location sources ]]
--!optimize 2
-- @modules serverlocation

local Location = {}
local scope, result, failure, currentStatus
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
  local candidates, seen = {}, {}
  local function add(callback)
    if type(callback) == "function" and not seen[callback] then
      candidates[#candidates + 1], seen[callback] = callback, true
    end
  end
  add(environment.request)
  add(environment.http_request)
  for _, name in ipairs({ "syn", "fluxus", "http" }) do
    if type(environment[name]) == "table" then
      add(environment[name].request)
    end
  end
  local status = { state = "reading", source = nil, error = nil }
  local function confirmed() return result.country ~= nil and result.estimated ~= true end
  local function readMetadata()
    local value = {}
    local ok, code = pcall(function() return game.ServerRegion end)
    local native = ok and text(code) and regions[string.upper(code)]
    if native then
      value = { country = native[1], city = native[2], source = "Região publicada pelo servidor" }
    end
    for _, root in ipairs({ game, workspace, game:GetService("ReplicatedStorage") }) do
      local objects = { root }
      for _, name in ipairs({ "ServerInfo", "ServerInformation", "ServerData" }) do
        local container = root:FindFirstChild(name)
        if container then
          objects[#objects + 1] = container
        end
      end
      for _, object in ipairs(objects) do
        value.country, value.city = value.country or attribute(object, "ServerCountry"), value.city or attribute(object, "ServerCity")
        local region = attribute(object, "ServerRegion")
        local mapped = region and regions[string.upper(region)]
        if mapped then
          value.country, value.city = value.country or mapped[1], value.city or mapped[2]
        end
      end
    end
    if value.country then
      value.source = value.source or "Informação publicada pelo jogo"
      result, failure, status.state, status.source = value, nil, "ready", value.source
    end
  end
  pcall(readMetadata)
  local cached = _G.ExodusServerLocationCache
  if
    not confirmed()
    and type(cached) == "table"
    and cached.placeId == game.PlaceId
    and cached.jobId == game.JobId
    and type(cached.expires) == "number"
    and cached.expires > os.time()
    and type(cached.value) == "table"
  then
    result, status.state = table.clone(cached.value), "ready"
  end
  local function fetch(url)
    local lastError
    for _, request in ipairs(candidates) do
      local ok, response = pcall(request, { Url = url, Method = "GET", Timeout = 5 })
      if ok and type(response) == "table" then
        local code = tonumber(response.StatusCode or response.status_code)
        local body = response.Body or response.body or response.ResponseBody
        if (not code or code >= 200 and code < 300) and type(body) == "string" then
          return body
        end
        lastError = "HTTP " .. tostring(code or "invalid response")
        if code == 429 then
          return nil, lastError
        end
      else
        lastError = tostring(response)
      end
    end
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then
      return body
    end
    return nil, lastError or tostring(body)
  end
  local peer, attempted, worker
  local function resolve(value)
    local ip = publicIP(value)
    if not owner.alive or not ip then
      return
    end
    peer = ip
    if confirmed() or result.country or worker or attempted == ip then
      return
    end
    attempted, status.state = ip, "looking-up"
    worker = owner.defer(function()
      local found
      -- Sequential providers; one live lookup and no location of the player's connection.
      for _, url in ipairs({ "https://ipwho.is/" .. ip, "https://ipapi.co/" .. ip .. "/json/" }) do
        if not owner.alive or confirmed() then
          break
        end
        local body, err = fetch(url)
        if not owner.alive then
          return
        end
        if body then
          local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(body) end)
          if ok and type(data) == "table" and (data.ip or data.query) == ip and data.success ~= false and not data.error then
            local country = text(data.country_name) or text(data.country)
            if country then
              found = { country = country, city = text(data.city), estimated = true, source = "Localização aproximada do ponto de conexão do servidor" }
              break
            end
          end
          err = "Resposta de geolocalização inválida"
        end
        status.error = tostring(err)
      end
      worker = nil
      if not owner.alive or confirmed() then
        return
      end
      if found then
        result, failure, status.state, status.source, status.error = found, nil, "ready", found.source, nil
        _G.ExodusServerLocationCache = { placeId = game.PlaceId, jobId = game.JobId, expires = os.time() + 600, value = table.clone(found) }
      else
        status.state, failure = "unavailable", "Não foi possível consultar o país do servidor."
      end
    end)
  end
  local current = false
  local function readLog(message)
    if type(message) ~= "string" then
      return
    end
    local job = message:match("[Jj]oining game ['\"]([^'\"]+)['\"]")
    if job then
      current = job == game.JobId
    end
    if type(game.JobId) == "string" and game.JobId ~= "" and message:find(game.JobId, 1, true) then
      current = true
    end
    if not current then
      return
    end
    local address = message:match("UDMUX Address%s*=%s*(%d+%.%d+%.%d+%.%d+)")
      or message:match("[Cc]onnecting to UDMUX server%s+(%d+%.%d+%.%d+%.%d+)")
      or message:match("[Cc]onnection accepted from%s+(%d+%.%d+%.%d+%.%d+)")
    if address then
      resolve(address)
    end
  end
  pcall(function() owner.connect(game:GetService("NetworkClient").ConnectionAccepted, resolve) end)
  pcall(function()
    local logs = game:GetService("LogService")
    owner.connect(logs.MessageOut, function(message) readLog(message) end)
    for _, entry in ipairs(logs:GetLogHistory()) do
      readLog(entry.message or entry.Message)
    end
  end)
  for _, service in ipairs({ "Workspace", "ReplicatedStorage" }) do
    local object = game:GetService(service)
    for _, name in ipairs({ "ServerCountry", "ServerCity", "ServerRegion" }) do
      owner.connect(object:GetAttributeChangedSignal(name), readMetadata)
    end
    owner.connect(object.ChildAdded, function(child)
      if
        child.Name == "ServerInfo"
        or child.Name == "ServerInformation"
        or child.Name == "ServerData"
        or child.Name == "ServerRegion"
        or child.Name == "ServerCountry"
      then
        pcall(readMetadata)
      end
    end)
  end
  owner.delay(8, function()
    if not result.country and not worker then
      failure, status.state = "O cliente não expôs a localização do servidor.", "unavailable"
    end
  end)
  -- Retry bounded failures, not requests every frame; confirmed metadata needs no polling.
  local retries = 0
  local function retry()
    if not owner.alive or result.country or retries >= 2 then
      return
    end
    retries += 1
    pcall(readMetadata)
    if peer and not worker then
      attempted = nil
      resolve(peer)
    end
    if not result.country then
      owner.delay(30, retry)
    end
  end
  owner.delay(30, retry)
  owner.add(function() status.state = "stopped" end)
  currentStatus = status
  return true
end
function Location.getStatus() return table.clone(currentStatus or { state = "stopped" }) end
function Location.snapshot() return table.clone(result or {}), failure end
Location.__contract = {
  access = { methods = { snapshot = "internal.read" } },
  provides = { "setup", "teardown", "snapshot", "getStatus" },
  requires = { Lifetime = "lifetime" },
  requiresMethods = { Lifetime = { "scope" } },
}
return Location
