-- [[ updater ]]

-- code
local Updater = {}
local CONFIG = {
  UPDATE_POLL_INTERVAL = 5,
  UPDATE_LOOP_INTERVAL = 1,
}

local UPDATE_WS_URL = "wss://ntfy.sh/exodus-v2-live-9f36c3d1e8b24a7c/ws"
function Updater.stop()
  local stop = _G.ExodusUpdateStop; _G.ExodusUpdateStop = nil
  if type(stop) == "function" then pcall(stop) end
  local socket = _G.ExodusUpdateSocket; _G.ExodusUpdateSocket = nil
  _G.ExodusUpdateToken = nil
  if socket then
    local close = socket.Close or socket.close
    if type(close) == "function" then pcall(close, socket) end
  end
end
function Updater.setup() return true end
function Updater.create(deps)
  local prepareLoader = deps.prepareLoader; local Exodus = deps.Exodus
  local HttpService = deps.HttpService; local resolveLatestRevision = deps.resolveLatestRevision
  local validRevision = deps.validRevision; local waitForMatchToEnd = deps.waitForMatchToEnd
  local waitForClashToEnd = deps.waitForClashToEnd; local notifyPersistent = deps.notifyPersistent
  local clearPersistent = deps.clearPersistent; local closeUpdateChannel = Updater.stop
  local sameRuntimeSignatures = deps.sameRuntimeSignatures; local authorizeRevision = deps.authorizeRevision
  local buildURLs = deps.buildURLs; local releaseSignatures = deps.signatures
  local reloadInFlight = false
  local reloadJob
  local function reloadLatest(onFailure, requestedRevision, automatic)
    if reloadJob and (automatic or not reloadJob.automatic) then return false, "reload already in progress" end
    local job = { automatic = automatic == true, session = _G.ExodusLoaderSessionToken }; reloadJob, reloadInFlight = job, true
    local function owns() return reloadJob == job end
    local function current() return owns() and _G.ExodusLoaderSessionToken == job.session and Exodus.Started == true end
    local function finish()
      if owns() then reloadJob, reloadInFlight = nil, false end
    end
    local function fail(message)
      if not owns() then return end
      finish(); warn("[Exodus Reload] " .. tostring(message))
      if automatic then
        clearPersistent("update"); notifyPersistent("Update failed. Check the console.", "critical", "critical")
        if type(_G.ExodusUIRestore) == "function" then pcall(_G.ExodusUIRestore, message) end
      end
      if type(onFailure) == "function" then task.defer(onFailure, message) end
    end
    if automatic then notifyPersistent("Updating...", "update", "info") else clearPersistent("update") end
    task.spawn(function()
      local completed, unexpected = xpcall(function()
        local revision, revisionError, _, signatures = resolveLatestRevision()
        if not current() then finish(); return end
        if not revision then fail(revisionError or "Version manifest unavailable"); return end
        if automatic and validRevision(Exodus.Revision) and revision:lower() == Exodus.Revision:lower() then
          clearPersistent("update"); finish()
          return
        end
        local chunk, prepareError = prepareLoader(revision, signatures)
        if not current() then finish(); return end
        if not chunk then fail(prepareError); return end
        if automatic then
          local ready, waited = waitForMatchToEnd(
            function() notifyPersistent("Update queued: waiting until you leave the match", "update", "info") end,
            current
          )
          if not ready or not current() then finish(); return end
          if not waitForClashToEnd(function() notifyPersistent("Update queued: waiting for clash to end", "update", "info") end, current) or not current() then finish(); return end
          if waited then
            local latest, err, _, latestSignatures = resolveLatestRevision()
            if not current() then finish(); return end
            if not latest then fail(err); return end
            if latest ~= revision then revision, signatures = latest, latestSignatures; chunk, prepareError = prepareLoader(revision, signatures) end
            if not chunk then fail(prepareError); return end
          end
          if type(_G.ExodusUIFadeOut) == "function" then pcall(_G.ExodusUIFadeOut) end
        end
        if not current() then finish(); return end
        _G.ExodusRequestedRevision = revision
        local ok, result = xpcall(chunk, function(err) return debug.traceback(tostring(err), 2) end)
        if not ok then
          _G.ExodusRequestedRevision = nil; fail(result)
          return
        end
        finish()
      end, function(err) return debug.traceback(tostring(err), 2) end)
      if not completed then
        if owns() then _G.ExodusRequestedRevision = nil end
        fail(unexpected)
      end
    end)
    return true
  end
  local function startUpdateChannel()
    closeUpdateChannel(); local sessionToken = _G.ExodusLoaderSessionToken
    local token = {}; _G.ExodusUpdateToken = token
    local messageConnection, closeConnection, socket, connecting, checking = nil, nil, nil, false, false; local nextSocketAttempt = 0
    local function active() return _G.ExodusUpdateToken == token and _G.ExodusLoaderSessionToken == sessionToken and Exodus.Started == true end
    local function disconnectSocket()
      if messageConnection then pcall(messageConnection.Disconnect, messageConnection); messageConnection = nil end
      if closeConnection then pcall(closeConnection.Disconnect, closeConnection); closeConnection = nil end
      local old = socket; socket = nil
      if _G.ExodusUpdateSocket == old then _G.ExodusUpdateSocket = nil end
      if old then
        pcall(function() old:Close() end)
      end
    end
    local function checkRevision()
      if not active() or checking or reloadInFlight then return end
      checking = true
      task.spawn(function()
        local ok, revision, _, _, signatures = pcall(resolveLatestRevision)
        if not ok or not active() or not validRevision(revision) then checking = false; return end
        local current = Exodus.Revision
        if validRevision(current) and revision:lower() == current:lower() then checking = false; return end
        if sameRuntimeSignatures(releaseSignatures, signatures) then
          local authorized, allowed = pcall(authorizeRevision, revision)
          if not active() or reloadInFlight then checking = false; return end
          if authorized and allowed then
            local urls = buildURLs(revision)
            if
              Exodus.Utils
              and type(Exodus.Utils.setModuleURLs) == "function"
              and Exodus.Utils.setModuleURLs(urls)
              and type(Exodus.Utils.getModuleURLsSnapshot) == "function"
            then
              Exodus.ModuleURLs = Exodus.Utils.getModuleURLsSnapshot()
            end
            releaseSignatures = signatures; deps.onSignatures(signatures)
            Exodus.Revision = revision; _G.ExodusLastLoadedRevision = revision
            checking = false; return
          end
        end
        checking = false; reloadLatest(nil, revision, true)
      end)
    end
    local function connectSocket()
      if not active() or socket or connecting or type(WebSocket) ~= "table" or type(WebSocket.connect) ~= "function" or os.clock() < nextSocketAttempt then return end
      nextSocketAttempt = os.clock() + 5; connecting = true
      task.spawn(function()
        local ok, candidate = pcall(WebSocket.connect, UPDATE_WS_URL); connecting = false
        if not active() then
          if candidate then
            pcall(function() candidate:Close() end)
          end
          return
        end
        if not ok or not candidate or not candidate.OnMessage or type(candidate.OnMessage.Connect) ~= "function" then
          if candidate then
            pcall(function() candidate:Close() end)
          end
          return
        end
        socket, _G.ExodusUpdateSocket = candidate, candidate
        messageConnection = candidate.OnMessage:Connect(function(raw)
          local decoded, event = pcall(HttpService.JSONDecode, HttpService, tostring(raw))
          if decoded and type(event) == "table" and event.event == "message" and validRevision(tostring(event.message or "")) then checkRevision() end
        end)
        if candidate.OnClose and type(candidate.OnClose.Connect) == "function" then
          closeConnection = candidate.OnClose:Connect(function()
            if socket == candidate then disconnectSocket() end
          end)
        end
        checkRevision()
      end)
    end
    _G.ExodusUpdateStop = function()
      if _G.ExodusUpdateToken == token then _G.ExodusUpdateToken = nil end
      disconnectSocket()
    end
    local nextRevisionCheck = 0
    task.spawn(function()
      while active() do
        connectSocket(); local time = os.clock()
        if time >= nextRevisionCheck then nextRevisionCheck = time + CONFIG.UPDATE_POLL_INTERVAL; checkRevision() end
        task.wait(CONFIG.UPDATE_LOOP_INTERVAL)
      end
    end)
    return true
  end
  return { reload = reloadLatest, start = startUpdateChannel, stop = Updater.stop }
end
Updater.__contract = { provides = { "setup", "create", "stop" }, requires = {} }

return Updater
