-- [[ smart return: one context-bound activation candidate, no sender ]]

-- code
local SmartReturn = {}
local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
function SmartReturn.setup() return true end
function SmartReturn.new()
  local state = {}; local detector = {}
  function detector.reset() state = {} end
  function detector.observe(s)
    if not s or not finite(s.at) or not finite(s.distance) or not finite(s.fullRadius) or not finite(s.killRadius) or s.fullRadius <= s.killRadius then detector.reset(); return nil end
    if state.ball ~= s.ball or (state.at and (s.at < state.at or s.at - state.at > 0.5)) then detector.reset() end
    state.ball, state.at = s.ball, s.at; local sensitivity = finite(s.sensitivity) and math.clamp(s.sensitivity, 0, 100) / 100 or 0.5
    local budget = 0.2 * (0.8 + 0.4 * sensitivity); local threshold = 0.65 - 0.5 * sensitivity
    local me = s.targetId == s.me
    if state.target == s.me and not me then
      local visit = state.visit
      if visit and finite(s.apAt) and s.apAt >= visit.at and s.apAt <= s.at and finite(s.apDistance) then
        visit.minimum = math.min(visit.minimum, s.apDistance)
        if finite(s.apRadius) and s.apRadius > s.killRadius then visit.radius = s.apRadius end
        if s.apDistance <= visit.radius then visit.entered = true end
      end
      if visit and visit.entered then
        local depth = math.clamp((visit.radius - visit.minimum) / (visit.radius - s.killRadius), 0, 1)
        state.outbound = { at = s.at, depth = depth, worsening = math.max(0, depth - (state.previousDepth or depth)) }; state.previousDepth = depth
      else
        state.outbound = nil
      end
      state.visit, state.returnedAt = nil, nil
    elseif me and state.target ~= s.me then
      state.returnedAt = state.outbound and s.at or nil; state.visit = { at = s.at, minimum = s.distance, radius = s.fullRadius, entered = s.distance <= s.fullRadius }
    end
    state.target = s.targetId
    if me and state.visit then
      local visit = state.visit
      if s.distance < visit.minimum then visit.minimum, visit.radius = s.distance, s.fullRadius end
      if s.distance <= s.fullRadius then visit.entered = true end
    end
    local outbound = state.outbound
    if not me or not outbound or not state.returnedAt then return nil end
    local elapsed = s.at - outbound.at
    if elapsed < 0 or elapsed > budget then state.outbound = nil; return nil end
    if finite(s.apAt) and s.apAt >= state.returnedAt then state.outbound = nil; return nil end
    local radius = s.fullRadius * (finite(s.partnerDistance) and s.partnerDistance < 16 and 1.2 or 1)
    if s.distance > radius or not s.partnerId then return nil end
    local returnTime = state.returnedAt - outbound.at; local score = outbound.depth + outbound.worsening + 0.25 * math.max(0, 1 - returnTime / budget)
    if score < threshold then return nil end
    return {
      partner = s.partnerId,
      returnTime = returnTime,
      minimumDepth = outbound.depth,
      worsening = outbound.worsening,
      score = score,
      threshold = threshold,
      budget = budget,
    }
  end
  return detector
end
SmartReturn.__contract = { provides = { "setup", "new" }, requires = {} }

return SmartReturn
