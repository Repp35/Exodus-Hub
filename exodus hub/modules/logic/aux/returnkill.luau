-- [[ fixed return timer with observed kill-radius cycles; no sender ]]

-- code
local ReturnKill = {}
local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
function ReturnKill.setup() return true end
function ReturnKill.new()
  local previous, context
  local detector = {}
  function detector.reset()
    previous, context = nil, nil
  end
  function detector.observe(s)
    if
      not s
      or not finite(s.at)
      or not finite(s.distance)
      or not finite(s.fullRadius)
      or not finite(s.killRadius)
      or not finite(s.targetId)
      or not finite(s.me)
    then
      detector.reset(); return nil
    end
    if previous and (previous.ball ~= s.ball or s.at < previous.at or s.at - previous.at > 0.2) then detector.reset() end
    if context and s.at - context.at > 0.2 then context = nil end
    local inside = s.distance <= s.killRadius; local leaving = previous and previous.targetId == s.me and s.targetId ~= s.me
    if not context and leaving and previous.inWindow == true then context = { at = s.at, inside = previous.inside, exited = false, cycles = 0, returned = false } end
    if context then
      if context.inside and not inside then context.exited = true end
      if not context.inside and inside and context.exited then context.cycles = context.cycles + 1; context.exited = false end
      context.inside = inside
      if previous and previous.targetId ~= s.me and s.targetId == s.me and s.distance <= s.fullRadius then context.returned, context.partner = true, previous.targetId end
    end
    previous = {
      at = s.at,
      ball = s.ball,
      targetId = s.targetId,
      inside = inside,
      inWindow = s.inWindow,
    }

    if
      context
      and context.returned
      and context.cycles >= 2
      and s.targetId == s.me
      and s.inWindow == true
      and s.distance <= s.fullRadius
      and s.partnerId == context.partner
    then
      return { partner = context.partner, cycles = context.cycles, elapsed = s.at - context.at }
    end
    return nil
  end
  return detector
end
ReturnKill.__contract = { provides = { "setup", "new" }, requires = {} }

return ReturnKill
