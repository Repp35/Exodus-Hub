-- [[ spam ]]
--!optimize 2

local inputState
local Spam = {}

local Utils
local Remote
local GameInfo
local AutoSpam
local DynamicParry
local spamObserver
local configObserver
local generation = 0
local running = false
local currentMode
local currentRate
local status = {
  phase = "stopped",
  lastRequestAt = 0,
  lastError = nil,
  lastErrorAt = -math.huge,
}

local samples = {}
local head = 1
local tail = 0
local attempts = 0
local accepted = 0

-- statistics
local function clearSamples()
  table.clear(samples)
  head, tail = 1, 0
  attempts, accepted = 0, 0
end
local function expireSamples(now)
  while head <= tail and now - samples[head].at >= 1 do
    local sample = samples[head]
    sample.live = false
    attempts -= sample.attempts
    accepted -= sample.accepted
    samples[head] = nil
    head += 1
  end
  if head > tail then
    clearSamples()
  elseif head > 128 then
    local count = tail - head + 1
    table.move(samples, head, tail, 1)
    for i = count + 1, tail do
      samples[i] = nil
    end
    head, tail = 1, count
  end
end
local function newSample()
  local now = os.clock()
  expireSamples(now)
  local sample = {
    at = now,
    attempts = 0,
    accepted = 0,
    live = true,
  }

  tail += 1
  samples[tail] = sample
  return sample
end

-- configuration
local function getRate()
  local mode = Utils.getConfigValue("SpamRateMode")
  if mode ~= "Auto" and mode ~= "CPF" and mode ~= "CPS" and mode ~= "MS" then
    mode = "CPS"
  end
  if mode == "Auto" then
    return mode, 1
  end
  local rate = tonumber(Utils.getConfigValue(mode)) or 0
  if rate ~= rate or rate <= 0 or rate == math.huge then
    return mode, 0
  end
  if mode == "MS" then
    rate = 1000 / rate
  end
  if rate == math.huge then
    return mode, 0
  end
  return mode, rate
end

-- state
local function transition(phase, reason)
  if status.phase == phase then
    return
  end
  local previous = status.phase
  status.phase = phase
  if Utils and type(Utils.recordTransition) == "function" then
    pcall(Utils.recordTransition, "Spam", previous, phase, reason)
  end
end
local function stop(reason)
  generation += 1
  running, currentMode, currentRate = false, nil, nil
  transition("stopped", reason)
end
local function reportError(utils, err)
  status.lastError = tostring(err)
  local now = os.clock()
  if now - status.lastErrorAt < 1 then
    return
  end
  status.lastErrorAt = now
  local ok, message = pcall(utils.recordError, "Spam", status.lastError)
  if not ok then
    warn("[Spam] " .. tostring(message))
  end
end

-- engine
local function run(token, mode, rate, U, R, G, A, D)
  local heartbeat = U.getRunService().Heartbeat
  local function active()
    return token == generation and U.isActive() and (inputState.isManualSpamActive() or inputState.isAutoSpamActive() or inputState.isDynamicSpamActive())
  end
  local function canSend()
    if not active() then
      return false
    end
    if inputState.isDynamicSpamActive() then
      return D.canSend()
    end
    if inputState.isManualSpamActive() then
      return A.canSendManual()
    end
    return A.canSend()
  end
  local prepared = type(R.prepareParry) == "function" and R.prepareParry(canSend) or function() return R.fireParry(1, canSend) end
  local function dispatch()
    if inputState.isDynamicSpamActive() then
      return R.fireNativeParry(canSend)
    end
    return prepared()
  end
  local function send(count)
    local sample
    for _ = 1, count do
      if not canSend() then
        break
      end
      if not sample then
        sample = newSample()
      end
      sample.attempts += 1
      attempts += 1
      status.lastRequestAt = os.clock()
      local result, detail = dispatch()
      if token ~= generation then
        break
      end
      if result == true then
        if sample.live then
          sample.accepted += 1
          accepted += 1
        end
        status.lastError = nil
      elseif detail == "Deflect recusado" or detail == "Deflect recusado pelo cliente" or detail == "Deflect cancelado" then
        status.lastError = nil
      else
        reportError(U, detail or "Remote.fireParry indisponível")
      end
      if detail == "Deflect cancelado" and not inputState.isManualSpamActive() then
        break
      end
    end
  end
  local function autoReady()
    local delay = G.getAutoSpamDelay()
    local minimum = G.getMinimumSpamInterval()
    if type(minimum) ~= "number" or minimum ~= minimum or minimum <= 0 or minimum == math.huge then
      minimum = 0.0301
    end
    return (delay == nil or (type(delay) == "number" and delay == delay and delay <= 0)) and os.clock() - status.lastRequestAt >= minimum
  end
  if mode == "CPF" then
    local credit, frameId, frameDuration = 0, 0, 1 / 60
    local lastSent, lastSpacing
    while active() do
      frameId += 1
      local owner, started = frameId, os.clock()
      credit += rate
      local count = math.floor(credit)
      credit -= count
      if count > 0 then
        local spacing = frameDuration / count
        local expires = started + frameDuration
        local function slot(index)
          if owner ~= frameId or not active() then
            return
          end
          local now = os.clock()
          if now >= expires or index >= count then
            return
          end
          local due = started + index * spacing
          if now < due then
            task.delay(due - now, slot, index)
            return
          end
          if (not lastSent or now - lastSent + 1e-9 >= math.max(spacing, lastSpacing or 0)) and canSend() then
            local ok, err = pcall(send, 1)
            if not ok then
              reportError(U, err)
              return
            end
            lastSent, lastSpacing = os.clock(), spacing
          end
          local nextIndex = math.max(index + 1, math.floor((os.clock() - started) / spacing) + 1)
          if nextIndex < count then
            task.delay(math.max(0, started + nextIndex * spacing - os.clock()), slot, nextIndex)
          end
        end
        slot(0)
      end
      local before = os.clock()
      local dt = heartbeat:Wait()
      local elapsed = os.clock() - before
      if type(dt) == "number" and dt == dt and dt > 0 then
        frameDuration = dt
      elseif elapsed > 0 then
        frameDuration = elapsed
      end
    end
    frameId += 1
    return
  end
  local frameDuration = 1 / 60
  local function interval()
    local requested
    if mode == "Auto" then
      requested = G.getMinimumSpamInterval()
      if type(requested) ~= "number" or requested ~= requested or requested <= 0 or requested == math.huge then
        requested = 0.0301
      end
    elseif mode == "CPF" then
      requested = frameDuration / rate
    else
      requested = 1 / rate
    end
    return requested
  end
  local nextAt = math.max(os.clock(), status.lastRequestAt > 0 and status.lastRequestAt + interval() or 0)
  while active() do
    local now = os.clock()
    if now >= nextAt then
      if canSend() and (mode ~= "Auto" or autoReady()) then
        send(1)
        nextAt = os.clock() + interval()
      else
        nextAt = now + interval()
      end
    end
    if not active() then
      break
    end
    if mode == "CPF" then
      local before = os.clock()
      local dt = heartbeat:Wait()
      local elapsed = os.clock() - before
      if type(dt) == "number" and dt == dt and dt > 0 then
        frameDuration = dt
      elseif elapsed > 0 then
        frameDuration = elapsed
      end
    else
      task.wait(math.max(0, nextAt - os.clock()))
    end
  end
end

-- synchronization
local function sync()
  if not Utils or not Remote then
    return
  end
  local mode, rate = getRate()
  local enabled = Utils.isActive() and rate > 0 and (inputState.isManualSpamActive() or inputState.isAutoSpamActive() or inputState.isDynamicSpamActive())
  if not enabled then
    if running then
      stop("spam_disabled")
    end
    return
  end
  if running and currentMode == mode and currentRate == rate then
    return
  end
  if running then
    stop("rate_changed")
  end
  generation += 1
  local token = generation
  local U, R, G, A, D = Utils, Remote, GameInfo, AutoSpam, DynamicParry
  running = true
  currentMode, currentRate = mode, rate
  transition("running", "spam_active")
  task.spawn(function()
    local ok, err = xpcall(function() run(token, mode, rate, U, R, G, A, D) end, function(message) return debug.traceback(tostring(message), 2) end)
    if token ~= generation then
      return
    end
    stop(ok and "spam_disabled" or "spam_error")
    if not ok then
      reportError(U, err)
      local retryToken = generation
      task.delay(0.03, function()
        if retryToken == generation and Utils == U and U.isActive() then
          sync()
        end
      end)
    end
  end)
end

-- lifecycle
function Spam.setup(deps)
  inputState = deps.InputState
  if type(deps) ~= "table" then
    return false, "dependências inválidas"
  end
  for name, methods in pairs(Spam.__contract.requiresMethods) do
    local dependency = deps[name]
    if type(dependency) ~= "table" then
      return false, "dependência ausente: " .. name
    end
    for _, method in ipairs(methods) do
      if method ~= "prepareParry" and type(dependency[method]) ~= "function" then
        return false, name .. "." .. method .. " ausente"
      end
    end
  end
  Spam.teardown()
  Utils = deps.Utils
  Remote = deps.Remote
  GameInfo = deps.GameInfo
  AutoSpam = deps.AutoSpam
  DynamicParry = deps.DynamicParry
  spamObserver = inputState.observeSpam(sync)
  configObserver = Utils.observeConfig(function(changes)
    if changes and (changes.SpamRateMode ~= nil or changes.CPS ~= nil or changes.CPF ~= nil or changes.MS ~= nil) then
      sync()
    end
  end)
  Utils.trackGlobal(spamObserver)
  Utils.trackGlobal(configObserver)
  sync()
  return true
end
function Spam.resetState()
  inputState.setAutoSpamActive(false)
  stop("reset")
  status.lastError = nil
  status.lastErrorAt = -math.huge
  clearSamples()
  local token = generation
  task.defer(function()
    if token == generation then
      sync()
    end
  end)
end
function Spam.teardown()
  stop("teardown")
  clearSamples()
  status.lastRequestAt = 0
  status.lastError = nil
  status.lastErrorAt = -math.huge
  if Utils then
    if spamObserver then
      Utils.untrackGlobal(spamObserver)
      spamObserver:Disconnect()
    end
    if configObserver then
      Utils.untrackGlobal(configObserver)
      configObserver:Disconnect()
    end
  end
  spamObserver, configObserver = nil, nil
  Utils, Remote, GameInfo, AutoSpam, DynamicParry = nil, nil, nil, nil, nil
end
function Spam.getStatus()
  expireSamples(os.clock())
  return {
    schema = Utils and Utils.apiVersion() or 1,
    phase = status.phase,
    lastRequestAt = status.lastRequestAt,
    lastError = status.lastError,
    attemptsLastSecond = attempts,
    acceptedLastSecond = accepted,
    cpfFps = 0,
    cpfClicks = 0,
    cpfCompensation = false,
  }
end

-- contract
Spam.__contract = {
  access = { methods = { resetState = "combat.runtime" } },
  requires = {
    InputState = "inputstate",
    Remote = "remote",
    Utils = "utils",
    GameInfo = "gameinfo",
    AutoSpam = "autospam",
    DynamicParry = "dynamicparry",
  },
  requiresMethods = {
    InputState = { "setAutoSpamActive", "isManualSpamActive", "isAutoSpamActive", "isDynamicSpamActive", "observeSpam" },
    Remote = {
      "fireParry",
      "prepareParry",
      "fireNativeParry",
    },
    AutoSpam = {
      "canSend",
      "canSendManual",
    },
    DynamicParry = {
      "canSend",
    },
    GameInfo = {
      "getAutoSpamDelay",
      "getMinimumSpamInterval",
    },
    Utils = {
      "apiVersion",
      "getConfigValue",
      "getRunService",
      "isActive",

      "observeConfig",
      "trackGlobal",
      "untrackGlobal",
      "recordError",
      "recordTransition",
    },
  },
  provides = {
    "setup",
    "resetState",
    "teardown",
    "getStatus",
  },
}

return Spam
