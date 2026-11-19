-- [[ spam ]]

-- module
local Spam = {}
local utils, remote, gameInfo, autoSpam, spamObserver, configObserver
local function traceback(err) return debug.traceback(tostring(err), 2) end
local generation, running, inFlight = 0, false, false
local dynamicParry
local currentMode, currentRate
local requestSequence = 0
local status = { phase = "stopped", lastRequestAt = 0, lastError = nil, lastErrorAt = -math.huge }
local samples, sampleHead, sampleTail, sampleAccepted, sampleAttempts = {}, 1, 0, 0, 0

-- configuration
local CONFIG = {
  ERROR_RETRY_INTERVAL = 0.03,
  MAX_FRAME_REQUESTS = 128,
  MAX_ACCUMULATION_SECONDS = 0.1,
}

-- helpers
local function clearSamples()
  table.clear(samples); sampleHead, sampleTail, sampleAccepted, sampleAttempts = 1, 0, 0, 0
end
local function expireSamples(time)
  while sampleHead <= sampleTail do
    local sample = samples[sampleHead]
    if time >= sample.at and time - sample.at < 1 then break end
    sample.live = false; sampleAccepted -= sample.accepted
    sampleAttempts -= sample.attempts; samples[sampleHead] = nil
    sampleHead += 1
  end
  if sampleHead > sampleTail then
    clearSamples()
  elseif sampleHead > 1024 and sampleHead > sampleTail / 2 then
    local count = sampleTail - sampleHead + 1
    for index = 1, count do
      samples[index] = samples[sampleHead + index - 1]
    end
    for index = count + 1, sampleTail do
      samples[index] = nil
    end
    sampleHead, sampleTail = 1, count
  end
end
local function readRate()
  local selected = utils.getConfigValue("SpamRateMode"); local mode = (selected == "Auto" or selected == "CPF" or selected == "MS") and selected or "CPS"
  if mode == "Auto" then return mode, 1 end
  local rate = tonumber(utils.getConfigValue(mode)) or 0
  if rate ~= rate or rate <= 0 or rate == math.huge then return mode, 0 end
  if mode == "MS" and 1000 / rate == math.huge then return mode, 0 end
  if mode == "CPF" and rate * 60 == math.huge then return mode, 0 end
  return mode, rate
end

-- state-control
local function transition(active, reason)
  local phase = active and "running" or "stopped"
  if status.phase == phase then return end
  local previous = status.phase; status.phase = phase
  if utils and type(utils.recordTransition) == "function" then utils.recordTransition("Spam", previous, phase, reason) end
end
local function cancel(reason)
  generation += 1; running, currentMode, currentRate, inFlight = false, nil, nil, false
  transition(false, reason)
end

-- dispatch
local function beginSample(time)
  expireSamples(time); local sample = { at = time, attempts = 0, accepted = 0, live = true }
  sampleTail += 1; samples[sampleTail] = sample
  return sample
end
local function request(boundUtils, dispatch, token, sample)
  if inFlight then return end
  requestSequence += 1; local requestToken = requestSequence
  inFlight = requestToken; status.lastRequestAt = os.clock()
  sample.attempts += 1; sampleAttempts += 1
  local result, detail = dispatch()
  if inFlight == requestToken then inFlight = false end
  if token ~= generation or utils ~= boundUtils then return end
  if result == true then
    if sample.live then sample.accepted += 1; sampleAccepted += 1 end
    status.lastError = nil; return true
  end
  if detail == "Deflect recusado pelo cliente" or detail == "Deflect recusado" or detail == "Deflect cancelado" then status.lastError = nil; return false, detail end
  local message = tostring(detail or "Remote.fireParry indisponível"); status.lastError = message
  local time = os.clock()
  if time - status.lastErrorAt >= 1 then
    status.lastErrorAt = time
    if type(boundUtils.recordError) == "function" then boundUtils.recordError("Spam", message) end
  end
  return false, detail
end

-- scheduler
local function sync()
  if not utils or not remote then return end
  local mode, rate = readRate(); local enabled = utils.isActive() and (utils.isManualSpamActive() or utils.isAutoSpamActive() or utils.isDynamicSpamActive()) and rate > 0
  if not enabled then
    if running then cancel("spam_disabled") end
    return
  end
  if running and currentMode == mode and currentRate == rate then return end
  if running then cancel("rate_changed") end
  generation += 1; local token, boundUtils, boundRemote, boundGameInfo = generation, utils, remote, gameInfo
  running, currentMode, currentRate = true, mode, rate; transition(true, "spam_active")
  local boundAutoSpam = autoSpam
  task.spawn(function()
    local function guard()
      return token == generation
        and boundUtils.isActive()
        and (boundUtils.isManualSpamActive() or boundUtils.isAutoSpamActive() or boundUtils.isDynamicSpamActive())
    end
    local function allowed()
      if not guard() then return false end
      if boundUtils.isDynamicSpamActive() then return dynamicParry.canSend() end
      if boundUtils.isManualSpamActive() then return boundAutoSpam.canSendManual() end
      return boundAutoSpam.canSend()
    end
    local ok, err = xpcall(function()
      local prepared = type(boundRemote.prepareParry) == "function" and boundRemote.prepareParry(allowed)
        or function() return boundRemote.fireParry(1, allowed) end
      local function dispatch()
        if boundUtils.isDynamicSpamActive() then return boundRemote.fireNativeParry(allowed) end
        return prepared()
      end
      local function burst()
        if not allowed() then return end
        local sample = beginSample(os.clock())
        for _ = 1, math.max(1, math.floor(rate)) do
          if not guard() then break end
          local sent, detail = request(boundUtils, dispatch, token, sample)
          if sent == false and detail == "Deflect cancelado" and not boundUtils.isManualSpamActive() then break end
        end
      end
      local heartbeat = mode == "CPF" and boundUtils.getRunService().Heartbeat; local credit, previous = 0, os.clock()
      local clicksPerSecond = mode == "MS" and 1000 / rate or rate
      if (boundUtils.isAutoSpamActive() or boundUtils.isDynamicSpamActive()) and allowed() then
        if mode == "CPF" then
          burst()
        elseif mode ~= "Auto" then
          request(boundUtils, dispatch, token, beginSample(os.clock()))
        else
          local delay = boundGameInfo.getAutoSpamDelay(); local minimum = boundGameInfo.getMinimumSpamInterval()
          if type(minimum) ~= "number" or minimum ~= minimum or minimum <= 0 or minimum == math.huge then minimum = 0.0301 end
          if (delay == nil or (type(delay) == "number" and delay == delay and delay <= 0)) and os.clock() - status.lastRequestAt >= minimum then
            request(boundUtils, dispatch, token, beginSample(os.clock()))
          end
        end
      end
      while guard() do
        if mode == "CPF" then
          heartbeat:Wait()
          if guard() then burst() end
        elseif mode ~= "Auto" then
          task.wait(); local time = os.clock()
          local delta = math.clamp(time - previous, 0, CONFIG.MAX_ACCUMULATION_SECONDS); previous = time
          if allowed() then
            credit = math.min(CONFIG.MAX_FRAME_REQUESTS, credit + (clicksPerSecond * delta)); local count = math.floor(credit)
            credit -= count
            if count > 0 then
              local sample = beginSample(time)
              for _ = 1, count do
                if not guard() then credit = 0; break end
                local sent, detail = request(boundUtils, dispatch, token, sample)
                if sent == false and detail == "Deflect cancelado" and not boundUtils.isManualSpamActive() then credit = 0; break end
              end
            end
          else
            credit = 0
          end
        else
          task.wait()
          if allowed() and not inFlight then
            local delay = boundGameInfo.getAutoSpamDelay(); local minimum = boundGameInfo.getMinimumSpamInterval()
            if type(minimum) ~= "number" or minimum ~= minimum or minimum <= 0 or minimum == math.huge then minimum = 0.0301 end
            if (delay == nil or (type(delay) == "number" and delay == delay and delay <= 0)) and os.clock() - status.lastRequestAt >= minimum then
              request(boundUtils, dispatch, token, beginSample(os.clock()))
            end
          end
        end
      end
    end, traceback)
    if token ~= generation then return end
    cancel(ok and "spam_disabled" or "spam_error")
    if not ok then
      status.lastError = tostring(err); local time = os.clock()
      if time - status.lastErrorAt >= 1 then
        status.lastErrorAt = time; local reported, reportError = pcall(boundUtils.recordError, "Spam", status.lastError)
        if not reported then warn("[Spam] " .. tostring(reportError)) end
      end
      local retryToken = generation
      task.delay(CONFIG.ERROR_RETRY_INTERVAL, function()
        if retryToken == generation and utils == boundUtils and boundUtils.isActive() then sync() end
      end)
    end
  end)
end

-- lifecycle
function Spam.setup(deps)
  if
    type(deps) ~= "table"
    or type(deps.Utils) ~= "table"
    or type(deps.Remote) ~= "table"
    or type(deps.GameInfo) ~= "table"
    or type(deps.DynamicParry) ~= "table"
    or type(deps.DynamicParry.canSend) ~= "function"
    or type(deps.AutoSpam) ~= "table"
    or type(deps.AutoSpam.canSend) ~= "function"
    or type(deps.AutoSpam.canSendManual) ~= "function"
    or type(deps.GameInfo.getAutoSpamDelay) ~= "function"
    or type(deps.GameInfo.getMinimumSpamInterval) ~= "function"
    or type(deps.Remote.fireParry) ~= "function"
    or type(deps.Utils.getConfigValue) ~= "function"
    or type(deps.Utils.isActive) ~= "function"
    or type(deps.Utils.isManualSpamActive) ~= "function"
    or type(deps.Utils.isAutoSpamActive) ~= "function"
    or type(deps.Utils.observeSpam) ~= "function"
    or type(deps.Utils.observeConfig) ~= "function"
  then
    return false, "dependência ausente: Remote ou Utils"
  end
  Spam.teardown(); dynamicParry = deps.DynamicParry
  utils, remote, gameInfo, autoSpam = deps.Utils, deps.Remote, deps.GameInfo, deps.AutoSpam; spamObserver = utils.observeSpam(sync)
  configObserver = utils.observeConfig(function(changes)
    if changes.SpamRateMode ~= nil or changes.CPS ~= nil or changes.CPF ~= nil or changes.MS ~= nil then sync() end
  end)
  utils.trackGlobal(spamObserver); utils.trackGlobal(configObserver)
  sync(); return true
end
function Spam.resetState()
  cancel("reset"); status.lastError, status.lastErrorAt = nil, -math.huge
  clearSamples(); local token = generation
  task.defer(function()
    if token == generation then sync() end
  end)
end
function Spam.teardown()
  cancel("teardown"); clearSamples()
  status.lastRequestAt, status.lastError, status.lastErrorAt = 0, nil, -math.huge
  if utils then
    if spamObserver then utils.untrackGlobal(spamObserver); spamObserver:Disconnect() end
    if configObserver then utils.untrackGlobal(configObserver); configObserver:Disconnect() end
  end
  spamObserver, configObserver, utils, remote, gameInfo, autoSpam = nil, nil, nil, nil, nil, nil
end

-- public-api
function Spam.getStatus()
  expireSamples(os.clock())
  return {
    schema = utils and utils.apiVersion() or 1,
    phase = status.phase,
    lastRequestAt = status.lastRequestAt,
    lastError = status.lastError,
    attemptsLastSecond = sampleAttempts,
    acceptedLastSecond = sampleAccepted,
    cpfFps = 0,
    cpfClicks = 0,
    cpfCompensation = false,
  }
end

-- contract
Spam.__contract = {
  requires = {
    Remote = "remote",
    Utils = "utils",
    GameInfo = "gameinfo",
    AutoSpam = "autospam",
    DynamicParry = "dynamicparry",
  },
  requiresMethods = {
    Remote = { "fireParry", "prepareParry", "fireNativeParry" },
    AutoSpam = { "canSend", "canSendManual" },
    DynamicParry = { "canSend" },
    GameInfo = { "getAutoSpamDelay", "getMinimumSpamInterval" },
    Utils = {
      "apiVersion",
      "getConfigValue",
      "getRunService",
      "isActive",
      "isManualSpamActive",
      "isAutoSpamActive",
      "isDynamicSpamActive",
      "observeSpam",
      "observeConfig",
      "trackGlobal",
      "untrackGlobal",
      "recordError",
      "recordTransition",
    },
  },
  provides = { "setup", "resetState", "teardown", "getStatus" },
}

return Spam
