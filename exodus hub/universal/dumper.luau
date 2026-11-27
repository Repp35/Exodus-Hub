-- [[ dumper ]]
--!optimize 2
-- @modules dumper

-- module
local Dumper = {}
local Discovery
local activeToken
local activeCallbacks
local status = {
  running = false,
  startedAt = 0,
  folder = nil,
  total = 0,
  processed = 0,
  saved = 0,
  failed = 0,
  bytecode = 0,
  syntaxWarnings = 0,
}

-- configuration
local CONFIG = {
  PREFIX = "SrcDump",
  PROGRESS_EVERY = 25,
  ERROR_BATCH = 8,
  API_TIMEOUT = 10,
  INSTANCE_BATCH = 5000,
  SCRIPT_BATCH = 50,
  SAVE_BYTECODE = true,
  SAVE_DISASSEMBLY = true,
  INCLUDE_NIL_INSTANCES = true,
}

local SCRIPT_CLASSES = {
  Script = true,
  LocalScript = true,
  ModuleScript = true,
}

local REMOTE_CLASSES = {
  RemoteEvent = true,
  RemoteFunction = true,
  UnreliableRemoteEvent = true,
  BindableEvent = true,
  BindableFunction = true,
}

local SYSTEM_NAMES = {
  CoreGui = true,
  CorePackages = true,
  RobloxGui = true,
  RobloxReplicatedStorage = true,
  CoreScripts = true,
  RobloxDefault = true,
  RobloxPlayerScript = true,
}

-- helpers
local function emit(callbacks, name, ...)
  local callback = callbacks and callbacks[name]
  if type(callback) == "function" then
    pcall(callback, ...)
  end
end
local function log(message)
  if type(print) == "function" then
    pcall(print, "[SrcDump] " .. tostring(message))
  end
end
local function line(value) return tostring(value):gsub("[\r\n]", " ") end
local function safeProperty(object, key, fallback)
  local ok, value = pcall(function() return object[key] end)
  if ok and value ~= nil then
    return value
  end
  return fallback
end
local function objectName(object) return tostring(safeProperty(object, "Name", "Unnamed")) end
local function objectClass(object) return tostring(safeProperty(object, "ClassName", "Unknown")) end
local function objectPath(object)
  local ok, value = pcall(function() return object:GetFullName() end)
  return ok and value or objectName(object)
end
local function isInstance(object) return typeof(object) == "Instance" end
local function safeFilename(value)
  local result = tostring(value):gsub("[^%w%._%-]", "_"):gsub("_+", "_"):sub(1, 80)
  if result == "" or result == "." or result == ".." then
    return "unnamed"
  end
  return result
end
local function ensureFolder(path)
  if type(isfolder) == "function" then
    local ok, exists = pcall(isfolder, path)
    if ok and exists then
      return true
    end
  end
  if type(makefolder) ~= "function" then
    return false, "makefolder is unavailable"
  end
  local ok, err = pcall(makefolder, path)
  if ok then
    return true
  end
  if type(isfolder) == "function" then
    local checked, exists = pcall(isfolder, path)
    if checked and exists then
      return true
    end
  end
  return false, tostring(err)
end
local function saveFile(path, content, createdFolders)
  if type(writefile) ~= "function" then
    return false, "writefile is unavailable"
  end
  local directory = path:match("^(.*)/[^/]+$")
  if directory and not createdFolders[directory] then
    local current = ""
    for part in directory:gmatch("[^/]+") do
      current = current == "" and part or current .. "/" .. part
      if not createdFolders[current] then
        local ok, err = ensureFolder(current)
        if not ok then
          return false, "cannot create " .. current .. ": " .. tostring(err)
        end
        createdFolders[current] = true
      end
    end
  end
  local ok, err = pcall(writefile, path, content)
  if not ok then
    return false, tostring(err)
  end
  return true
end
local function allowed(object, allowDetached)
  if not isInstance(object) then
    return false
  end
  local current = object
  for _ = 1, 200 do
    if current == game then
      return true
    end
    if SYSTEM_NAMES[objectName(current)] then
      return false
    end
    local parent = safeProperty(current, "Parent")
    if not isInstance(parent) then
      return allowDetached == true
    end
    current = parent
  end
  return false
end
local function serialize(value)
  if type(value) == "string" then
    return string.format("%q", value)
  end
  local ok, result = pcall(tostring, value)
  return ok and line(result) or "<unavailable>"
end
local function attributes(object)
  local ok, values = pcall(function() return object:GetAttributes() end)
  if not ok or type(values) ~= "table" then
    return "{}"
  end
  local result = {}
  for key, value in pairs(values) do
    result[#result + 1] = line(key) .. "=" .. serialize(value)
  end
  table.sort(result)
  return "{" .. table.concat(result, ", ") .. "}"
end
local function tags(object, collection)
  if not collection then
    return "[]"
  end
  local ok, values = pcall(function() return collection:GetTags(object) end)
  if not ok or type(values) ~= "table" then
    return "[]"
  end
  table.sort(values)
  return "[" .. table.concat(values, ", ") .. "]"
end
local function errorText(value)
  local text = type(value) == "string" and value or ("returned " .. type(value))
  return line(text)
end
local SOURCE_ERRORS = {
  "failed to get script bytecode",
  "failed to get bytecode",
  "failed to decompile",
  "failed to extract",
  "decompilation failed",
  "decompiler error",
  "decompiler timed out",
  "script has no bytecode",
  "no bytecode available",
  "empty bytecode",
  "server scripts are impossible",
  "invalid argument",
  "server error",
  "decompilation error",
}

local function sourceError(value)
  local lower = tostring(value):lower():gsub("^%s*%-%-%[%[", ""):gsub("^%s*%-%-+%s*", ""):gsub("^%s+", "")
  for _, phrase in ipairs(SOURCE_ERRORS) do
    if lower:sub(1, #phrase) == phrase then
      return line(value)
    end
  end
  return nil
end
local function timedCall(token, fn, argument)
  if token.cancelled then
    return false, "Dump canceled"
  end
  local deadline = os.clock() + CONFIG.API_TIMEOUT
  local finished, success, result = false, false, nil
  local worker = task.defer(function()
    local ok, value = pcall(fn, argument)
    success, result, finished = ok, value, true
  end)
  while not finished and not token.cancelled and os.clock() < deadline do
    task.wait()
  end
  if finished then
    return success, result
  end
  if worker and type(task.cancel) == "function" then
    pcall(task.cancel, worker)
  end
  return false, token.cancelled and "Dump canceled" or "API timed out"
end
local function getGameName(token)
  local ok, product = timedCall(token, function() return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId) end)
  if ok and type(product) == "table" and type(product.Name) == "string" and product.Name:match("%S") then
    return product.Name
  end
  local name = safeProperty(game, "Name")
  if type(name) == "string" and name:match("%S") and name ~= "Game" and name ~= "game" then
    return name
  end
  return "Place_" .. tostring(game.PlaceId)
end
local function nextFolder(gameName)
  local base = CONFIG.PREFIX .. "_" .. safeFilename(gameName)
  if type(isfolder) ~= "function" then
    return base .. "_" .. tostring(os.time())
  end
  local index = 1
  while true do
    local candidate = base .. "_" .. index
    local ok, exists = pcall(isfolder, candidate)
    if not ok then
      return base .. "_" .. tostring(os.time())
    end
    if not exists then
      return candidate
    end
    index += 1
  end
end
-- dump
local function run(token, callbacks)
  if type(writefile) ~= "function" or type(makefolder) ~= "function" then
    return nil, "writefile and makefolder are required"
  end
  local gameName = getGameName(token)
  if token.cancelled then
    return nil, "Dump canceled"
  end
  local createdFolders = {}
  local base = nextFolder(gameName)
  local status = token.status
  local function callAPI(fn, argument) return timedCall(token, fn, argument) end
  local function save(path, content)
    if token.cancelled then
      return false, "Dump canceled"
    end
    return saveFile(path, content, createdFolders)
  end
  status.folder = base
  for _, path in ipairs({ base, base .. "/scripts", base .. "/remotes" }) do
    local ok, err = ensureFolder(path)
    if not ok then
      return nil, "cannot create " .. path .. ": " .. tostring(err)
    end
    createdFolders[path] = true
  end
  if CONFIG.SAVE_BYTECODE then
    local ok, err = ensureFolder(base .. "/bytecode")
    if not ok then
      return nil, "cannot create bytecode folder: " .. tostring(err)
    end
    createdFolders[base .. "/bytecode"] = true
  end
  if CONFIG.SAVE_DISASSEMBLY then
    local ok, err = ensureFolder(base .. "/disassembly")
    if not ok then
      return nil, "cannot create disassembly folder: " .. tostring(err)
    end
    createdFolders[base .. "/disassembly"] = true
  end
  emit(callbacks, "onStatus", "Finding scripts...")
  local discovery = Discovery.create(token, {
    include = allowed,
    class = objectClass,
    path = objectPath,
    name = objectName,
    classes = SCRIPT_CLASSES,
    batch = CONFIG.INSTANCE_BATCH,
    detached = CONFIG.INCLUDE_NIL_INSTANCES,
    call = callAPI,
  })
  token.discovery = discovery
  discovery.scan()
  if token.cancelled then
    return nil, "Dump canceled"
  end
  local catalog, candidates, discoveryErrors = discovery.catalog, discovery.candidates, discovery.errors
  local lookup = discovery.resolve
  status.total = #candidates
  emit(callbacks, "onProgress", 0, #candidates)
  local decompiler, disassembler = lookup("decompile"), lookup("disassemble")
  local compiler = lookup("loadstring")
  local closureReaders, readers, knownClosures, knownReaders = {}, {}, {}, {}
  for _, name in ipairs({ "getscriptclosure", "getscriptfunction" }) do
    local fn, label = lookup(name)
    if fn and not knownClosures[fn] then
      knownClosures[fn] = true
      closureReaders[#closureReaders + 1] = { name = label, fn = fn }
    end
  end
  for _, name in ipairs({ "getscriptbytecode", "dumpstring" }) do
    local fn, label = lookup(name)
    if fn and not knownReaders[fn] then
      knownReaders[fn] = true
      readers[#readers + 1] = { name = label, fn = fn }
    end
  end
  local manifest, errors = {}, table.clone(discoveryErrors)
  local saved, failed, bytecodes, cacheHits, syntaxWarnings = 0, 0, 0, 0, 0
  local sourceCache, unresolved = {}, {}
  local folderByInstance, usedFolderNames = { [game] = "" }, { [""] = { _nilinstances = true } }
  local function folderFor(item)
    local chain, current = {}, nil
    for _, node in ipairs(item.parents) do
      if node.instance == game or folderByInstance[node.instance] ~= nil then
        current = node.instance
        break
      end
      chain[#chain + 1] = node
    end
    local folder = current and folderByInstance[current] or "_NilInstances"
    for i = #chain, 1, -1 do
      local node = chain[i]
      local used = usedFolderNames[folder]
      if not used then
        used = {}
        usedFolderNames[folder] = used
      end
      local name = safeFilename(node.name)
      local candidate, suffix = name, 1
      while used[candidate:lower()] do
        suffix += 1
        candidate = name .. "__" .. suffix
      end
      used[candidate:lower()] = true
      folder = folder == "" and candidate or folder .. "/" .. candidate
      folderByInstance[node.instance] = folder
    end
    return folder
  end
  local function concurrent(items, process, batchSize)
    batchSize = batchSize or CONFIG.SCRIPT_BATCH
    local first = 1
    while first <= #items do
      if token.cancelled then
        return false, "Dump canceled"
      end
      local pending, failure = 0, nil
      local last = math.min(#items, first + batchSize - 1)
      for index = first, last do
        local itemIndex, item = index, items[index]
        pending += 1
        task.defer(function()
          local ok, err = xpcall(function() process(itemIndex, item) end, function(message) return debug.traceback(tostring(message), 2) end)
          if not ok then
            failure = failure or err
          end
          pending -= 1
        end)
      end
      repeat
        task.wait()
      until pending == 0
      if failure then
        return false, failure
      end
      first = last + 1
    end
    return not token.cancelled, token.cancelled and "Dump canceled" or nil
  end
  local processed = 0
  local function extract(index, item)
    if token.cancelled then
      return nil, "Dump canceled"
    end
    local object, attempts = item.instance, {}
    local source, method, bytecode, closure
    local function attempt(label, fn, argument, validateSource)
      if token.cancelled then
        return nil
      end
      local success, value = callAPI(fn, argument)
      if token.cancelled then
        return nil
      end
      if not success then
        attempts[#attempts + 1] = label .. ": error: " .. errorText(value)
        return nil
      end
      if type(value) ~= "string" or #value == 0 then
        attempts[#attempts + 1] = label .. ": empty or invalid return (" .. type(value) .. ")"
        return nil
      end
      if validateSource then
        if not value:match("%S") then
          attempts[#attempts + 1] = label .. ": empty source"
          return nil
        end
        local problem = sourceError(value)
        if problem then
          attempts[#attempts + 1] = label .. ": " .. problem
          return nil
        end
      end
      attempts[#attempts + 1] = label .. ": returned " .. #value .. " bytes"
      return value
    end
    do
      if token.cancelled then
        return nil, "Dump canceled"
      end
      local sourceOk, directSource = pcall(function() return object.Source end)
      if sourceOk and type(directSource) == "string" and directSource:match("%S") and not sourceError(directSource) then
        source, method = directSource, "Source"
        attempts[#attempts + 1] = "Source: available"
      else
        attempts[#attempts + 1] = "Source: " .. (sourceOk and "empty or unavailable" or errorText(directSource))
      end
      if not bytecode and #readers > 0 then
        for _, reader in ipairs(readers) do
          bytecode = attempt(reader.name .. "(instance)", reader.fn, object, false)
          if bytecode then
            break
          end
        end
      end
      if not source and bytecode and sourceCache[bytecode] then
        source, method = sourceCache[bytecode], "cached bytecode"
        cacheHits += 1
      end
      if not source and decompiler then
        source = attempt("decompile(instance)", decompiler, object, true)
        if source then
          method = "decompile(instance)"
        end
      end
      if not source and bytecode and decompiler then
        source = attempt("decompile(bytecode)", decompiler, bytecode, true)
        if source then
          method = "decompile(bytecode)"
        end
      end
      if not source and decompiler then
        for _, reader in ipairs(closureReaders) do
          local success, value = callAPI(reader.fn, object)
          if success and type(value) == "function" then
            closure = value
            attempts[#attempts + 1] = reader.name .. ": function obtained"
            source = attempt("decompile(" .. reader.name .. ")", decompiler, closure, true)
            if source then
              method = "decompile(" .. reader.name .. ")"
              break
            end
          else
            attempts[#attempts + 1] = reader.name .. ": " .. (success and ("returned " .. type(value)) or errorText(value))
          end
        end
      end
    end
    local syntaxStatus, syntaxError = "unavailable", nil
    if source and compiler then
      local checked, result = callAPI(function(text)
        local chunk, reason = compiler(text)
        if type(chunk) == "function" then
          return true
        end
        return tostring(reason or "compiler returned no function")
      end, source)
      syntaxStatus = checked and result == true and "valid" or "warning"
      if syntaxStatus == "warning" then
        syntaxWarnings += 1
        status.syntaxWarnings = syntaxWarnings
        syntaxError = errorText(result)
        errors[#errors + 1] = "[SOURCE_SYNTAX_WARNING] " .. line(item.path) .. " | " .. syntaxError
      end
    end
    if source and syntaxStatus ~= "warning" and bytecode and not sourceCache[bytecode] then
      sourceCache[bytecode] = source
    end
    if not decompiler then
      attempts[#attempts + 1] = "decompile: unavailable"
    end
    if #readers == 0 then
      attempts[#attempts + 1] = "bytecode readers unavailable"
    end
    local folder = folderFor(item)
    local filename = ("%s__%s_%04d"):format(safeFilename(item.name), objectClass(object), index)
    local stem = folder ~= "" and folder .. "/" .. filename or filename
    if bytecode and CONFIG.SAVE_BYTECODE then
      local byteOk, byteError = save(base .. "/bytecode/" .. stem .. ".bin", bytecode)
      if byteOk then
        bytecodes += 1
      else
        attempts[#attempts + 1] = "save bytecode: " .. tostring(byteError)
      end
    end
    local context = line(safeProperty(object, "RunContext", "unavailable"))
    local header = table.concat({
      "-- SrcDump",
      "-- index: " .. index,
      "-- class: " .. objectClass(object),
      "-- path: " .. line(item.path),
      "-- discovered_by: " .. item.origin,
      "-- run_context: " .. context,
      "-- method: " .. tostring(method or "none"),
      "-- syntax_status: " .. syntaxStatus,
      syntaxError and ("-- syntax_warning: " .. line(syntaxError)) or "",
      "",
    }, "\n")
    local entry = {
      item = item,
      stem = stem,
      index = index,
      bytecode = bytecode,
      closure = closure,
      attempts = attempts,
      source = source,
    }

    if source then
      local savedOk, saveError = save(base .. "/scripts/" .. stem .. ".lua", header .. source .. "\n")
      if savedOk then
        saved += 1
        manifest[index] = "[OK] " .. line(item.path) .. " | " .. method .. " | scripts/" .. stem .. ".lua"
      else
        attempts[#attempts + 1] = "save source: " .. tostring(saveError)
        unresolved[#unresolved + 1] = entry
        failed += 1
        manifest[index] = "[PENDING] " .. line(item.path)
      end
    else
      unresolved[#unresolved + 1] = entry
      manifest[index] = "[PENDING] " .. line(item.path)
      failed += 1
    end
    processed += 1
    status.total = #candidates
    status.processed, status.saved, status.failed, status.bytecode = processed, saved, failed, bytecodes
    if processed == 1 or processed % CONFIG.PROGRESS_EVERY == 0 then
      emit(callbacks, "onProgress", processed, #candidates, item.path)
    end
  end
  local extracted, extractError = concurrent(candidates, extract)
  discovery.stop()
  if not extracted then
    return nil, extractError
  end
  local collection
  pcall(function() collection = game:GetService("CollectionService") end)
  emit(callbacks, "onStatus", "Saving game data...")
  local tree = { "SrcDump - instances", "", "" }
  local remotes = { "SrcDump - remotes and bindables", "" }
  local remoteCount, instanceCount = 0, 0
  for index, item in ipairs(catalog) do
    if token.cancelled then
      return nil, "Dump canceled"
    end
    local object = item.instance
    if allowed(object, item.detached) then
      local class = objectClass(object)
      local detail = ("[%s] %s | discovered=%s | attributes=%s | tags=%s"):format(
        class,
        line(item.path or objectPath(object)),
        item.origin,
        attributes(object),
        tags(object, collection)
      )
      instanceCount += 1
      tree[#tree + 1] = detail
      if REMOTE_CLASSES[class] then
        remoteCount += 1
        remotes[#remotes + 1] = detail
      end
    end
    if index % CONFIG.INSTANCE_BATCH == 0 then
      task.wait()
    end
  end
  tree[2] = "total=" .. instanceCount
  remotes[2] = "total=" .. remoteCount
  local treeOk, treeError = save(base .. "/tree.txt", table.concat(tree, "\n") .. "\n")
  if not treeOk then
    return nil, "cannot save tree.txt: " .. tostring(treeError)
  end
  local remoteOk, remoteError = save(base .. "/remotes/remotes.txt", table.concat(remotes, "\n") .. "\n")
  if not remoteOk then
    return nil, "cannot save remotes.txt: " .. tostring(remoteError)
  end
  local info = {
    "SrcDump - game information",
    "place_id=" .. tostring(game.PlaceId),
    "game_id=" .. tostring(game.GameId),
    "job_id=" .. tostring(game.JobId),
    "game_name=" .. line(gameName),
    "creator_id=" .. tostring(game.CreatorId),
    "creator_type=" .. tostring(game.CreatorType),
    "place_version=" .. tostring(game.PlaceVersion),
    "instances=" .. instanceCount,
    "scripts=" .. #candidates,
    "remotes=" .. remoteCount,
  }

  info[#info + 1] = "product_name=" .. line(gameName)
  local infoOk, infoError = save(base .. "/game_info.txt", table.concat(info, "\n") .. "\n")
  if not infoOk then
    return nil, "cannot save game_info.txt: " .. tostring(infoError)
  end
  local function finalizeFailure(_, entry)
    if entry.source then
      manifest[entry.index] = "[ERROR] " .. line(entry.item.path) .. " | write failed"
      errors[#errors + 1] = "[WRITE_ERROR] " .. line(entry.item.path) .. "\n  " .. table.concat(entry.attempts, "\n  ")
    else
      if CONFIG.SAVE_DISASSEMBLY and disassembler then
        local function disassemble(argument)
          local ok, value = callAPI(disassembler, argument)
          if ok and type(value) == "string" and #value > 0 and not sourceError(value) then
            return value
          end
          return nil
        end
        local assembly = disassemble(entry.item.instance)
        if not assembly and entry.bytecode then
          assembly = disassemble(entry.bytecode)
        end
        if not assembly and entry.closure then
          assembly = disassemble(entry.closure)
        end
        if assembly then
          save(base .. "/disassembly/" .. entry.stem .. ".txt", assembly .. "\n")
        end
      end
      local category = entry.bytecode and "bytecode read; source extraction failed" or "bytecode extraction failed"
      errors[#errors + 1] = "[SOURCE_ERROR] "
        .. line(entry.item.path)
        .. " | "
        .. objectClass(entry.item.instance)
        .. " | "
        .. category
        .. " | run_context="
        .. line(safeProperty(entry.item.instance, "RunContext", "unavailable"))
        .. " | discovered_by="
        .. entry.item.origin
        .. "\n  "
        .. table.concat(entry.attempts, "\n  ")
      manifest[entry.index] = "[ERROR] " .. line(entry.item.path) .. " | " .. category
    end
    status.saved, status.failed, status.bytecode = saved, failed, bytecodes
  end
  local finalized, finalizeError = concurrent(unresolved, finalizeFailure, CONFIG.ERROR_BATCH)
  if not finalized then
    return nil, finalizeError
  end
  if token.cancelled then
    return nil, "Dump canceled"
  end
  status.saved, status.failed = saved, failed
  local manifestOk, manifestError = save(base .. "/manifest.txt", table.concat(manifest, "\n") .. "\n")
  if not manifestOk then
    return nil, "cannot save manifest.txt: " .. tostring(manifestError)
  end
  local errorsOk, errorsError = save(base .. "/errors.txt", #errors > 0 and table.concat(errors, "\n\n") .. "\n" or "No errors.\n")
  if not errorsOk then
    return nil, "cannot save errors.txt: " .. tostring(errorsError)
  end
  local capabilitiesOk, capabilitiesError = save(base .. "/capabilities.txt", table.concat(discovery.capabilities, "\n") .. "\n")
  if not capabilitiesOk then
    return nil, "cannot save capabilities.txt: " .. tostring(capabilitiesError)
  end
  local summaryOk, summaryError = save(
    base .. "/summary.txt",
    table.concat({
      "SrcDump",
      "folder=" .. base,
      "game_name=" .. line(gameName),
      "total_found=" .. #candidates,
      "decompiled_and_saved=" .. saved,
      "source_syntax_warnings=" .. syntaxWarnings,
      "source_syntax_validation=" .. (compiler and "available" or "unavailable"),
      "failed=" .. failed,
      "bytecode_saved=" .. bytecodes,
      "source_cache_hits=" .. cacheHits,
      "discovered_live=" .. discovery.stats.live,
      "discovered_gc=" .. discovery.stats.gc,
      "discovered_detached_descendants=" .. discovery.stats.detached,
      "extraction_workers=" .. CONFIG.SCRIPT_BATCH,
      "discovery_errors=" .. #discoveryErrors,
      "instances=" .. instanceCount,
      "remotes=" .. remoteCount,
      "note=Only content accessible to the client environment can be captured.",
      "",
    }, "\n")
  )
  if not summaryOk then
    return nil, "cannot save summary.txt: " .. tostring(summaryError)
  end
  log(("Finished: %d saved, %d failed, %d source warnings. Folder: %s"):format(saved, failed, syntaxWarnings, base))
  return {
    folder = base,
    total = #candidates,
    saved = saved,
    failed = failed,
    bytecode = bytecodes,
    syntaxWarnings = syntaxWarnings,
  }
end

-- lifecycle
function Dumper.setup(deps)
  Dumper.stop()
  Discovery = deps.Discovery
  return true
end
function Dumper.start(callbacks)
  if activeToken then
    return false, "A dump is already running"
  end
  if type(callbacks) ~= "table" then
    callbacks = {}
  end
  local token = { cancelled = false }
  activeToken, activeCallbacks = token, callbacks
  status = {
    running = true,
    startedAt = os.clock(),
    folder = nil,
    total = 0,
    processed = 0,
    saved = 0,
    failed = 0,
    bytecode = 0,
    syntaxWarnings = 0,
  }

  token.status = status
  task.spawn(function()
    local ok, result, reason = xpcall(
      function() return run(token, callbacks) end,
      function(errorValue) return debug and type(debug.traceback) == "function" and debug.traceback(tostring(errorValue), 2) or tostring(errorValue) end
    )
    if token.discovery then
      token.discovery.stop()
    end
    if activeToken ~= token then
      return
    end
    local callbacks = activeCallbacks
    activeToken, activeCallbacks = nil, nil
    status.running = false
    if token.cancelled then
      emit(callbacks, "onCanceled")
      return
    end
    if not ok or not result then
      local message = not ok and result or reason or "Dump failed"
      emit(callbacks, "onError", message)
      return
    end
    status.folder = result.folder
    status.syntaxWarnings = result.syntaxWarnings
    status.total, status.saved, status.failed, status.bytecode = result.total, result.saved, result.failed, result.bytecode
    emit(callbacks, "onComplete", table.clone(result))
  end)
  return true
end
function Dumper.stop()
  status.running = false
  if activeToken then
    local callbacks = activeCallbacks
    activeToken.cancelled = true
    if activeToken.discovery then
      activeToken.discovery.stop()
    end
    activeToken, activeCallbacks = nil, nil
    emit(callbacks, "onCanceled")
    log("Dump canceled.")
  end
  return true
end
function Dumper.isRunning() return activeToken ~= nil end
function Dumper.getStatus() return table.clone(status) end
function Dumper.teardown() return Dumper.stop() end

-- contract
Dumper.__contract = {
  access = { default = "tooling.execute" },
  requires = { Discovery = "dumpdiscovery" },
  requiresMethods = { Discovery = { "create" } },
  provides = { "setup", "start", "stop", "isRunning", "getStatus", "teardown" },
}

return Dumper
