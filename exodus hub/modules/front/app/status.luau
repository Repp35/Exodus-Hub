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
  if stats.frozen == true then
    if text(stats.deceasedName) then out.travel[#out.travel + 1] = stats.deceasedName .. " died" end
    if positive(stats.fatalTravelTime) then out.travel[#out.travel + 1] = string.format("Fatal return: %.0f ms", stats.fatalTravelTime * 1000) end
    if positive(stats.penultimateTravelTime) then out.travel[#out.travel + 1] = string.format("Previous return: %.0f ms", stats.penultimateTravelTime * 1000) end
  elseif finite(stats.travelElapsed) and stats.travelElapsed >= 0 and text(stats.travelTargetName) then
    out.travel[#out.travel + 1] = string.format("%s: %.0f ms", stats.travelTargetName, stats.travelElapsed * 1000)
  end
  if positive(stats.lastTravelTime) then out.travel[#out.travel + 1] = string.format("Last return: %.0f ms", stats.lastTravelTime * 1000) end
  return out
end
StatusView.__contract = { provides = { "setup", "format" }, requires = {} }

return StatusView
