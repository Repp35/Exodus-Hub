
-- [[ spam ]]

local Spam = {}

local Utils, Remote, GameInfo, AutoSpam, DynamicParry
local spamObserver, configObserver
local generation, running = 0, false
local currentMode, currentRate

local status = {
    phase = "stopped",
    lastRequestAt = 0,
    lastError = nil,
    lastErrorAt = -math.huge,
}

local samples = {}
local head, tail = 1, 0
local attempts, accepted = 0, 0

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

    if mode ~= "Auto" and mode ~= "CPF"
        and mode ~= "CPS" and mode ~= "MS" then
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
    if status.phase == phase then return end

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
    if now - status.lastErrorAt < 1 then return end

    status.lastErrorAt = now

    local ok, message = pcall(
        utils.recordError,
        "Spam",
        status.lastError
    )

    if not ok then
        warn("[Spam] " .. tostring(message))
    end
end

-- engine

local function run(token, mode, rate, U, R, G, A, D)
    local heartbeat = U.getRunService().Heartbeat

    local function active()
        return token == generation
            and U.isActive()
            and (
                U.isManualSpamActive()
                or U.isAutoSpamActive()
                or U.isDynamicSpamActive()
            )
    end

    local function canSend()
        if not active() then return false end

        if U.isDynamicSpamActive() then
            return D.canSend()
        end

        if U.isManualSpamActive() then
            return A.canSendManual()
        end

        return A.canSend()
    end

    local prepared = type(R.prepareParry) == "function"
        and R.prepareParry(canSend)
        or function()
            return R.fireParry(1, canSend)
        end

    local function dispatch()
        if U.isDynamicSpamActive() then
            return R.fireNativeParry(canSend)
        end

        return prepared()
    end

    local function send(count)
        local sample

        for _ = 1, count do
            if not canSend() then break end

            if not sample then
                sample = newSample()
            end

            sample.attempts += 1
            attempts += 1

            status.lastRequestAt = os.clock()

            local result, detail = dispatch()

            if token ~= generation then break end

            if result == true then
                if sample.live then
                    sample.accepted += 1
                    accepted += 1
                end

                status.lastError = nil

            elseif detail == "Deflect recusado"
                or detail == "Deflect recusado pelo cliente"
                or detail == "Deflect cancelado" then

                status.lastError = nil
            else
                reportError(U, detail or "Remote.fireParry indisponível")
            end

            if detail == "Deflect cancelado"
                and not U.isManualSpamActive() then
                break
            end
        end
    end

    local function autoReady()
        local delay = G.getAutoSpamDelay()
        local minimum = G.getMinimumSpamInterval()

        if type(minimum) ~= "number"
            or minimum ~= minimum
            or minimum <= 0
            or minimum == math.huge then
            minimum = 0.0301
        end

        return (
            delay == nil
            or (
                type(delay) == "number"
                and delay == delay
                and delay <= 0
            )
        ) and os.clock() - status.lastRequestAt >= minimum
    end

    -- scheduler

    local credit = 0

    local function tick(dt)
        if not canSend() then
            credit = 0
            return
        end

        if mode == "Auto" then
            if autoReady() then
                send(1)
            end
            return
        end

        credit += mode == "CPF" and rate or rate * dt

        local count = math.floor(credit)
        credit -= count

        if count > 0 then
            send(count)
        end
    end

    -- immediate activation

    local skipFirstFrame = false

    if mode == "CPF" then
        tick(0)
        skipFirstFrame = true

    elseif mode == "Auto" then
        tick(0)

    elseif (U.isAutoSpamActive() or U.isDynamicSpamActive())
        and canSend() then

        send(1)
        credit = 0
    end

    -- main loop

    local previous = os.clock()
    while active() do
        heartbeat:Wait()
        local now = os.clock()
        local dt = math.max(0, now - previous)
        previous = now

        if not active() then break end

        if skipFirstFrame then
            skipFirstFrame = false
        else
            tick(dt)
        end
    end
end

-- synchronization

local function sync()
    if not Utils or not Remote then return end

    local mode, rate = getRate()

    local enabled = Utils.isActive()
        and rate > 0
        and (
            Utils.isManualSpamActive()
            or Utils.isAutoSpamActive()
            or Utils.isDynamicSpamActive()
        )

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
    local U, R, G, A, D =
        Utils, Remote, GameInfo, AutoSpam, DynamicParry

    running = true
    currentMode, currentRate = mode, rate

    transition("running", "spam_active")

    task.spawn(function()
        local ok, err = xpcall(function()
            run(token, mode, rate, U, R, G, A, D)
        end, function(message)
            return debug.traceback(tostring(message), 2)
        end)

        if token ~= generation then return end

        stop(ok and "spam_disabled" or "spam_error")

        if not ok then
            reportError(U, err)

            local retryToken = generation

            task.delay(0.03, function()
                if retryToken == generation
                    and Utils == U
                    and U.isActive() then
                    sync()
                end
            end)
        end
    end)
end

-- lifecycle

function Spam.setup(deps)
    if type(deps) ~= "table" then
        return false, "dependências inválidas"
    end

    for name, methods in pairs(Spam.__contract.requiresMethods) do
        local dependency = deps[name]

        if type(dependency) ~= "table" then
            return false, "dependência ausente: " .. name
        end

        for _, method in ipairs(methods) do
            if method ~= "prepareParry"
                and type(dependency[method]) ~= "function" then

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

    spamObserver = Utils.observeSpam(sync)

    configObserver = Utils.observeConfig(function(changes)
        if changes and (
            changes.SpamRateMode ~= nil
            or changes.CPS ~= nil
            or changes.CPF ~= nil
            or changes.MS ~= nil
        ) then
            sync()
        end
    end)

    Utils.trackGlobal(spamObserver)
    Utils.trackGlobal(configObserver)

    sync()
    return true
end

function Spam.resetState()
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
    Utils, Remote, GameInfo, AutoSpam, DynamicParry =
        nil, nil, nil, nil, nil
end

-- public API

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
    requires = {
        Remote = "remote",
        Utils = "utils",
        GameInfo = "gameinfo",
        AutoSpam = "autospam",
        DynamicParry = "dynamicparry",
    },

    requiresMethods = {
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

    provides = {
        "setup",
        "resetState",
        "teardown",
        "getStatus",
    },
}

return Spam
