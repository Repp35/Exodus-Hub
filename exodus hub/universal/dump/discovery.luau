-- [[ dump discovery ]]
--!optimize 2
-- @modules dumpdiscovery

local Discovery = {}
function Discovery.setup() return true end
function Discovery.create(token, options)
  local catalog, candidates, errors, capabilities = {}, {}, {}, {}
  local providers, providerSeen, seen, expanded, resolved, gcSeen = {}, {}, {}, {}, {}, {}
  local stats = { live = 0, gc = 0, detached = 0 }
  local connection
  local function provider(value, name)
    if type(value) ~= "table" or providerSeen[value] then
      return
    end
    providerSeen[value] = true
    providers[#providers + 1] = { value = value, name = name }
  end
  if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok then
      provider(value, "getgenv")
    end
  end
  if type(getfenv) == "function" then
    local ok, value = pcall(getfenv)
    if ok then
      provider(value, "getfenv")
    end
  end
  provider(_G, "_G")
  local roots = #providers
  for index = 1, roots do
    local root = providers[index]
    for _, name in ipairs({ "syn", "krnl", "fluxus" }) do
      local ok, value = pcall(function() return root.value[name] end)
      if ok then
        provider(value, root.name .. "." .. name)
      end
    end
  end
  local function resolve(name)
    if resolved[name] then
      return resolved[name].fn, resolved[name].label
    end
    for _, root in ipairs(providers) do
      local ok, value = pcall(function() return root.value[name] end)
      if ok and type(value) == "function" then
        local label = root.name .. "." .. name
        resolved[name] = { fn = value, label = label }
        capabilities[#capabilities + 1] = name .. "=" .. label
        return value, label
      end
    end
    resolved[name] = {}
    capabilities[#capabilities + 1] = name .. "=unavailable"
  end
  local function record(object, origin, detached)
    if token.cancelled or typeof(object) ~= "Instance" then
      return
    end
    local item = seen[object]
    if not item then
      item = { instance = object, origin = origin, detached = detached, class = options.class(object) }
      seen[object] = item
      catalog[#catalog + 1] = item
    elseif detached then
      item.detached = true
    end
    if not item.enqueued and options.classes[item.class] and options.include(object, item.detached) then
      item.path, item.enqueued, item.name, item.parents = options.path(object), true, options.name(object), {}
      local node = object
      for _ = 1, 200 do
        local ok, parent = pcall(function() return node.Parent end)
        if not ok or typeof(parent) ~= "Instance" then
          break
        end
        item.parents[#item.parents + 1] = { instance = parent, name = options.name(parent) }
        if parent == game then
          break
        end
        node = parent
      end
      candidates[#candidates + 1] = item
      if origin == "game.DescendantAdded" then
        stats.live += 1
      end
      if origin == "getgc.script" then
        stats.gc += 1
      end
      if origin:find(".descendants", 1, true) then
        stats.detached += 1
      end
    end
    return item
  end
  local function expand(object, origin, detached)
    record(object, origin, detached)
    if typeof(object) ~= "Instance" or object == game or not detached or expanded[object] or not options.include(object, true) then
      return
    end
    local readable, parent = pcall(function() return object.Parent end)
    if not readable or typeof(parent) == "Instance" then
      return
    end
    expanded[object] = true
    local ok, children = pcall(function() return object:GetDescendants() end)
    if not ok then
      errors[#errors + 1] = origin .. ": descendants: " .. tostring(children)
      return
    end
    for index, child in ipairs(children) do
      if token.cancelled then
        return
      end
      record(child, origin .. ".descendants", true)
      if index % options.batch == 0 then
        task.wait()
      end
    end
  end
  local function scanAPI(name, used)
    local api, label = resolve(name)
    if not api or used[api] then
      return
    end
    used[api] = true
    local ok, values = options.call(api)
    if not ok or type(values) ~= "table" then
      errors[#errors + 1] = label .. ": discovery: " .. tostring(values)
      return
    end
    local processed = 0
    for _, object in pairs(values) do
      if token.cancelled then
        return
      end
      expand(object, label, options.detached)
      processed += 1
      if processed % options.batch == 0 then
        task.wait()
      end
    end
  end
  local function scanGC()
    local api, label = resolve("getgc")
    if not api then
      return
    end
    local ok, values = options.call(api, false)
    if not ok or type(values) ~= "table" then
      errors[#errors + 1] = label .. ": discovery: " .. tostring(values)
      return
    end
    local visited = 0
    for _, value in pairs(values) do
      if token.cancelled then
        return
      end
      visited += 1
      if type(value) == "function" then
        local scoped, environment = pcall(getfenv, value)
        local readable, object = false, nil
        if scoped and type(environment) == "table" then
          readable, object = pcall(function() return environment.script end)
        end
        if readable and typeof(object) == "Instance" and not gcSeen[object] and options.classes[options.class(object)] then
          gcSeen[object] = true
          record(object, "getgc.script", options.detached)
          local root = object
          for _ = 1, 200 do
            local valid, parent = pcall(function() return root.Parent end)
            if not valid or typeof(parent) ~= "Instance" or parent == game then
              break
            end
            root = parent
          end
          expand(root, "getgc.root", options.detached)
        end
      end
      if visited % options.batch == 0 then
        task.wait()
      end
    end
  end
  local function stop()
    if connection then
      connection:Disconnect()
      connection = nil
    end
  end
  local function scan()
    local connected, result = pcall(function()
      return game.DescendantAdded:Connect(function(object) record(object, "game.DescendantAdded", false) end)
    end)
    if connected then
      connection = result
    else
      errors[#errors + 1] = "game.DescendantAdded: " .. tostring(result)
    end
    record(game, "game", false)
    local ok, descendants = pcall(function() return game:GetDescendants() end)
    if ok then
      for index, object in ipairs(descendants) do
        if token.cancelled then
          return
        end
        record(object, "game:GetDescendants", false)
        if index % options.batch == 0 then
          task.wait()
        end
      end
    else
      errors[#errors + 1] = "game:GetDescendants: " .. tostring(descendants)
    end
    local used = {}
    for _, name in ipairs({ "getscripts", "getrunningscripts", "getnilinstances", "getloadedmodules", "getinstances" }) do
      scanAPI(name, used)
    end
    scanGC()
  end
  return { catalog = catalog, candidates = candidates, errors = errors, capabilities = capabilities, stats = stats, scan = scan, stop = stop, resolve = resolve }
end
Discovery.__contract = { access = { default = "tooling.execute" }, provides = { "setup", "create" }, requires = {} }
return Discovery
