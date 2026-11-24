-- [[ Phantom Ball readouts ]]

local Telemetry = {}
function Telemetry.setup() return true end
local StatusView = {}
local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local function positive(v) return finite(v) and v > 0 end
local function object(v) return type(v) == "table" and v or {} end
local function text(v) return type(v) == "string" and v ~= "" and v ~= "nil" and v ~= "null" end
function StatusView.format(data)
  data = object(data)
  local ap, auto = object(data.ap), object(data.autoSpam)
  local stats = object(auto.clashStats)
  local out = { ap = {}, gates = {}, travel = {}, distance = {} }
  if positive(ap.maxObservedCps) then
    out.ap[1] = string.format("AP max: %.2f CPS", ap.maxObservedCps)
  end
  local predictionGate = object(auto.gates).prediction
  if text(predictionGate) then
    out.gates[#out.gates + 1] = "Prediction: " .. predictionGate
  end
  if text(auto.lastActivationReason) then
    out.gates[#out.gates + 1] = "Last activation: " .. auto.lastActivationReason
  end
  if text(auto.lastStopReason) then
    out.gates[#out.gates + 1] = "Last deactivation: " .. auto.lastStopReason
  end
  local dynamic = object(data.dynamicParry)
  if text(dynamic.lastStopReason) and dynamic.lastStopReason ~= "player_died" and dynamic.lastStopReason ~= "opponent_left_or_died" then
    out.gates[#out.gates + 1] = "Dynamic deactivation: " .. dynamic.lastStopReason
  end
  local start = object(stats.startSample)
  if finite(start.distance) and start.distance >= 0 then
    out.distance[#out.distance + 1] = string.format("Start: %.1f studs", start.distance)
  end
  local sample = object(stats.endSample)
  if finite(sample.distance) and sample.distance >= 0 then
    out.distance[#out.distance + 1] = string.format(stats.frozen == true and "Final distance: %.1f studs" or "Distance: %.1f studs", sample.distance)
  end
  local speed = positive(sample.speed) and sample.speed or stats.speed
  if positive(speed) then
    out.distance[#out.distance + 1] = string.format("Speed: %.0f", speed)
  end
  if positive(stats.currentCps) then
    out.distance[#out.distance + 1] = string.format("Clash: %.2f CPS", stats.currentCps)
  end
  if positive(stats.duration) then
    out.distance[#out.distance + 1] = string.format("Duration: %.2fs", stats.duration)
  end
  local travel = object(data.travel or stats)
  if finite(travel.incomingRecordedAt) or finite(travel.outgoingRecordedAt) then
    local function tti(value) return finite(value) and value >= 0 and string.format("%.0f ms", value * 1000) or "unavailable" end
    out.travel[1] = "Last target TTI: " .. tti(travel.lastIncomingTTI)
    out.travel[2] = "Previous target TTI: " .. tti(travel.previousIncomingTTI)
    if finite(travel.outgoingRecordedAt) then
      out.travel[#out.travel + 1] = "Opponent target TTI: " .. tti(travel.lastOutgoingTTI)
      out.travel[#out.travel + 1] = "Previous opponent TTI: " .. tti(travel.previousOutgoingTTI)
    end
    return out
  end
  if finite(travel.travelElapsed) and travel.travelElapsed >= 0 and text(travel.travelTargetName) then
    out.travel[#out.travel + 1] = string.format("Target (%s): %.0f ms", travel.travelTargetName, travel.travelElapsed * 1000)
  end
  if positive(travel.lastTravelTime) then
    local who = text(travel.lastTravelTargetName) and (" (" .. travel.lastTravelTargetName .. ")") or ""
    out.travel[#out.travel + 1] = string.format("Last target%s: %.0f ms", who, travel.lastTravelTime * 1000)
  end
  if positive(travel.fatalTravelTime) then
    local who = text(travel.deceasedName) and (" (" .. travel.deceasedName .. ")") or ""
    out.travel[#out.travel + 1] = string.format("Last death%s: %.0f ms", who, travel.fatalTravelTime * 1000)
  end
  return out
end

function Telemetry.create(loaded)
  local Utils = loaded.utils
  local lastActivation, lastStop = nil, nil
  local lastPeak, lastDistance = nil, {}
  local lastTravel = {}
  local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
  local function validText(v) return type(v) == "string" and v ~= "" and v ~= "nil" and v ~= "null" end
  local function read()
    local enabled = {
      ap = Utils.getConfigValue("APMaxCpsVisible") == true,
      gates = Utils.getConfigValue("ClashGateInfoVisible") == true,
      travel = Utils.getConfigValue("ClashTravelTimeVisible") == true,
      distance = Utils.getConfigValue("ClashDistanceVisible") == true,
    }

    local data = {}
    if enabled.ap then
      data.ap = loaded.status.get("autoparry")
    end
    if enabled.gates then
      data.dynamicParry = loaded.status.get("dynamicparry")
    end
    if enabled.gates or enabled.travel or enabled.distance then
      data.autoSpam = loaded.status.get("autospam")
    end
    if type(data.autoSpam) == "table" then
      local status = data.autoSpam
      if
        type(status.lastActivationReason) == "string"
        and status.lastActivationReason ~= ""
        and status.lastActivationReason ~= "nil"
        and status.lastActivationReason ~= "null"
      then
        lastActivation = status.lastActivationReason
      end
      if type(status.lastStopReason) == "string" and status.lastStopReason ~= "" and status.lastStopReason ~= "nil" and status.lastStopReason ~= "null" then
        lastStop = status.lastStopReason
      end
    end
    local status = type(data.autoSpam) == "table" and table.clone(data.autoSpam) or {}
    status.lastActivationReason, status.lastStopReason = lastActivation, lastStop
    data.autoSpam = status
    local peak = type(data.ap) == "table" and data.ap.maxObservedCps
    if finite(peak) and peak > 0 and (not lastPeak or peak > lastPeak) then
      lastPeak = peak
    end
    data.ap = { maxObservedCps = lastPeak }
    local stats = type(status.clashStats) == "table" and status.clashStats or {}
    if stats.partnerId and stats.partnerId ~= lastTravel.partnerId then
      lastTravel.partnerId = stats.partnerId
      lastTravel.outgoingRecordedAt, lastTravel.lastOutgoingTTI, lastTravel.previousOutgoingTTI = nil, nil, nil
    end
    if finite(stats.outgoingRecordedAt) then
      lastTravel.outgoingRecordedAt, lastTravel.lastOutgoingTTI, lastTravel.previousOutgoingTTI =
        stats.outgoingRecordedAt, stats.lastOutgoingTTI, stats.previousOutgoingTTI
    end
    if finite(stats.incomingRecordedAt) then
      lastTravel.incomingRecordedAt, lastTravel.lastIncomingTTI, lastTravel.previousIncomingTTI =
        stats.incomingRecordedAt, stats.lastIncomingTTI, stats.previousIncomingTTI
    end
    if finite(stats.travelElapsed) and stats.travelElapsed >= 0 and validText(stats.travelTargetName) then
      lastTravel.travelElapsed, lastTravel.travelTargetName = stats.travelElapsed, stats.travelTargetName
    end
    if finite(stats.lastTravelTime) and stats.lastTravelTime > 0 then
      lastTravel.lastTravelTime, lastTravel.lastTravelTargetName = stats.lastTravelTime, stats.lastTravelTargetName
    end
    if finite(stats.fatalTravelTime) and stats.fatalTravelTime > 0 then
      lastTravel.fatalTravelTime, lastTravel.deceasedName = stats.fatalTravelTime, stats.deceasedName
    end
    data.travel = lastTravel
    local panels = StatusView.format(data)
    if #panels.distance > 0 then
      lastDistance = panels.distance
    end
    panels.distance = lastDistance
    return panels
  end

  local cachedAt, cached = -math.huge, {}
  local function value(id)
    local now = os.clock()
    if now - cachedAt >= 0.05 then
      cached, cachedAt = read(), now
    end
    return table.concat(cached[id] or {}, "\n")
  end
  local result = {}
  for _, spec in ipairs({
    { "distance", "ClashDistanceVisible", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 0) },
    { "travel", "ClashTravelTimeVisible", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -20) },
    { "gates", "ClashGateInfoVisible", Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0) },
    { "ap", "APMaxCpsVisible", Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0) },
  }) do
    result[#result + 1] = { id = spec[1], key = spec[2], anchor = spec[3], position = spec[4], read = function() return value(spec[1]) end }
  end
  return result
end
Telemetry.__contract = { provides = { "setup", "create" }, requires = {} }
return Telemetry
