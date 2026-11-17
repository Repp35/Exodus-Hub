-- [[ deflectgeometry ]]

-- code
local DeflectGeometry = {}
function DeflectGeometry.setup() return true end
local function finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function validBallSpeed(value) return finite(value) and value >= 0 and value <= 1000 end
local EMPTY_OPTIONS = {}
function DeflectGeometry.create(GameInfo, CONFIG)
  local Geometry = {}
  function Geometry.getDeflectGeometry(speed, window, factor, _scaleBase, latencyOverride, options)
    if not validBallSpeed(speed) then return nil end
    options = type(options) == "table" and options or EMPTY_OPTIONS; local includeResilience = options.resilience ~= false
    local range = includeResilience and GameInfo.getDeflectRange() or CONFIG.RANGE_BASE
    if not finite(range) or range <= 0 then range = CONFIG.RANGE_BASE end
    if window == "ap" then
      local low, high = GameInfo.getBallSpeedLimits()
      if not finite(low) or not finite(high) or high <= low then return nil end
      local fraction = math.clamp((speed - low) / (high - low), 0, 1); local actual = GameInfo.getDeflectWindow(speed, includeResilience)
      if not finite(actual) then return nil end
      window = math.max(
        0,
        actual
          + (CONFIG.AP_WINDOW_LOW_SPEED - CONFIG.WINDOW_BASE) * (1 - fraction)
          + (CONFIG.AP_WINDOW_HIGH_SPEED - (CONFIG.WINDOW_BASE - CONFIG.WINDOW_SPREAD)) * fraction
      )
    elseif not finite(window) then
      window = GameInfo.getDeflectWindow(speed, includeResilience)
      if finite(window) then local minimum = finite(options.minimumWindow) and math.max(0, options.minimumWindow) or 0; window = math.max(window, minimum) end
    end
    if not finite(window) or window < 0 then return nil end
    local latency = options.ping == false and 0 or (finite(latencyOverride) and latencyOverride or GameInfo.getAveragePing())
    if not finite(latency) or latency < 0 then latency = 0 end
    factor = finite(factor) and math.max(0, factor) or 1; local base = range
    return {
      fullRadius = base + speed * (window + latency) * factor,
      pureRadius = CONFIG.RANGE_BASE,
      noWindowParryRadius = range,
      resilienceBonus = range - CONFIG.RANGE_BASE,
      pingRadius = speed * latency * factor,
      deflectWindow = window,
      effectiveWindow = (window + latency) * factor,
      leadTime = window + latency,
      windowFactor = factor,
    }
  end
  function Geometry.getAutoParryGeometry(speed, factor, frameLead, latencyOverride)
    if not validBallSpeed(speed) then return nil end
    local low, high = GameInfo.getBallSpeedLimits()
    if not finite(low) or not finite(high) or high <= low then return nil end
    local window = GameInfo.getDeflectWindow(speed, false); local range = GameInfo.getDeflectRange()
    if not finite(range) or range <= 0 then range = CONFIG.RANGE_BASE end
    if not finite(window) or window < 0 then return nil end
    local latency = finite(latencyOverride) and math.max(0, latencyOverride) or GameInfo.getAveragePing()
    if not finite(latency) then latency = 0 end
    local factorValue = finite(factor) and math.clamp(factor, 0, 1) or 0.3; local frame = finite(frameLead) and math.clamp(frameLead, 0, 0.15) or 1 / 60
    local networkLead = latency + frame; local lead = latency + math.min(window * factorValue + frame, window * 0.95)
    return {
      fullRadius = range + CONFIG.AUTO_PARRY_TRIGGER_PADDING + speed * lead,
      pureRadius = CONFIG.RANGE_BASE,
      noWindowParryRadius = range,
      resilienceBonus = range - CONFIG.RANGE_BASE,
      pingRadius = speed * latency,
      deflectWindow = window,
      effectiveWindow = lead,
      leadTime = lead,
      serverLeadTime = window + latency,
      windowFactor = factorValue,
      triggerPadding = CONFIG.AUTO_PARRY_TRIGGER_PADDING,
      networkLead = networkLead,
      uplinkLead = latency,
      frameLead = frame,
      autoParry = true,
      killRadius = 4,
    }
  end
  function Geometry.getProjectedDeflectRadius(geometry, closingSpeed)
    if type(geometry) ~= "table" or not finite(geometry.noWindowParryRadius) or not finite(geometry.effectiveWindow) or not finite(closingSpeed) then return nil end
    return geometry.noWindowParryRadius + math.max(0, closingSpeed) * geometry.effectiveWindow
  end
  return Geometry
end
DeflectGeometry.__contract = { provides = { "setup", "create" }, requires = {} }

return DeflectGeometry
