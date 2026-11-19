-- [[ status presentation: read-only formatting of module observations ]]

-- code
local StatusView = {}
local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local function positive(v) return finite(v) and v > 0 end
local function object(v) return type(v) == "table" and v or {} end
local function text(v) return type(v) == "string" and v ~= "" and v ~= "nil" and v ~= "null" end
function StatusView.setup() return true end
function StatusView.format(data)
  data = object(data); local ap, auto = object(data.ap), object(data.autoSpam)
  local stats = object(auto.clashStats); local out = { ap = {}, gates = {}, travel = {}, distance = {} }
  if positive(ap.maxObservedCps) then out.ap[1] = string.format("AP max: %.2f CPS", ap.maxObservedCps) end
  if text(auto.lastActivationReason) then out.gates[#out.gates + 1] = "Last activation: " .. auto.lastActivationReason end
  if text(auto.lastStopReason) then out.gates[#out.gates + 1] = "Last deactivation: " .. auto.lastStopReason end
  local dynamic = object(data.dynamicParry)
  if text(dynamic.lastStopReason) and dynamic.lastStopReason ~= "player_died" and dynamic.lastStopReason ~= "opponent_left_or_died" then
    out.gates[#out.gates + 1] = "Dynamic deactivation: " .. dynamic.lastStopReason
  end
  local start = object(stats.startSample)
  if finite(start.distance) and start.distance >= 0 then out.distance[#out.distance + 1] = string.format("Start: %.1f studs", start.distance) end
  local sample = object(stats.endSample)
  if finite(sample.distance) and sample.distance >= 0 then
    out.distance[#out.distance + 1] = string.format(stats.frozen == true and "Final distance: %.1f studs" or "Distance: %.1f studs", sample.distance)
  end
  local speed = positive(sample.speed) and sample.speed or stats.speed
  if positive(speed) then out.distance[#out.distance + 1] = string.format("Speed: %.0f", speed) end
  if positive(stats.currentCps) then out.distance[#out.distance + 1] = string.format("Clash: %.2f CPS", stats.currentCps) end
  if positive(stats.duration) then out.distance[#out.distance + 1] = string.format("Duration: %.2fs", stats.duration) end
  local travel = object(data.travel or stats)
  if finite(travel.incomingRecordedAt) or finite(travel.outgoingRecordedAt) then
    local function tti(value) return finite(value) and value >= 0 and string.format("%.0f ms", value * 1000) or "unavailable" end
    out.travel[1] = "Last target TTI: " .. tti(travel.lastIncomingTTI); out.travel[2] = "Previous target TTI: " .. tti(travel.previousIncomingTTI)
    if finite(travel.outgoingRecordedAt) then
      out.travel[#out.travel + 1] = "Opponent target TTI: " .. tti(travel.lastOutgoingTTI); out.travel[#out.travel + 1] = "Previous opponent TTI: " .. tti(travel.previousOutgoingTTI)
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
    local who = text(travel.deceasedName) and (" (" .. travel.deceasedName .. ")") or ""; out.travel[#out.travel + 1] = string.format("Last death%s: %.0f ms", who, travel.fatalTravelTime * 1000)
  end
  return out
end
StatusView.__contract = { provides = { "setup", "format" }, requires = {} }

return StatusView
