-- [[ mcp ballistics ]]
--!native
--!optimize 2
local Ballistics = {}
local units
local STEP = 0.05
function Ballistics.setup(deps)
  units = deps.Units
  return true
end
local function coefficients(time, drag)
  local n = math.floor(time / STEP)
  local fraction = time - n * STEP
  if math.abs(1 - drag) < 1e-7 then
    return n * STEP + fraction, STEP * STEP * n * (n - 1) / 2 + fraction * STEP * n
  end
  local power = drag ^ n
  local sum = (1 - power) / (1 - drag)
  return STEP * sum + fraction * power, STEP / (1 - drag) * (STEP * (n - sum) + fraction * (1 - power))
end
local function safeFloor(hit, destination, params)
  if hit.Normal.Y < 0.65 or hit.Material == Enum.Material.Water or (units.toBlocks(hit.Position) - destination).Magnitude > 15 / 32 then
    return false
  end
  local block = hit.Instance:GetAttribute("BlockKey")
  if block == "lava" or block == "water" then
    return false
  end
  local feet = units.toBlocks(hit.Position) + Vector3.new(0, 3 / 64, 0)
  for _, offset in ipairs({ Vector3.zero, Vector3.new(13 / 64, 0, 0), Vector3.new(-13 / 64, 0, 0), Vector3.new(0, 0, 13 / 64), Vector3.new(0, 0, -13 / 64) }) do
    if workspace:Raycast(units.toWorld(feet + offset), units.offset(0, 2, 0), params) then
      return false
    end
    local floor = workspace:Raycast(units.toWorld(feet + offset), units.offset(0, -0.25, 0), params)
    if not floor or floor.Normal.Y < 0.65 or floor.Material == Enum.Material.Water then
      return false
    end
    local key = floor.Instance:GetAttribute("BlockKey")
    if key == "lava" or key == "water" then
      return false
    end
  end
  return true
end
local function clear(origin, velocity, gravity, drag, duration, destination, params)
  local position = origin
  for _ = 1, math.ceil((duration + STEP) / STEP) do
    local offset = velocity * STEP
    local hit = workspace:Raycast(units.toWorld(position), units.toWorld(offset), params)
    if hit then
      return safeFloor(hit, destination, params)
    end
    position += offset
    velocity = velocity * drag - Vector3.new(0, gravity * STEP, 0)
  end
  return false
end
function Ballistics.solve(origin, destination, speed, gravity, params, maxFlight, drag)
  drag, maxFlight = drag or 0.99, maxFlight or 6
  if speed <= 0 or gravity <= 0 or drag <= 0 or drag > 1 or maxFlight <= STEP then
    return nil
  end
  local delta = destination - origin
  local function required(time)
    local travel, drop = coefficients(time, drag)
    local velocity = (delta + Vector3.new(0, gravity * drop, 0)) / travel
    return velocity:Dot(velocity) - speed * speed, velocity
  end
  local low, lowError = 0.001, required(0.001)
  for tick = 1, math.ceil(maxFlight / STEP) do
    local high = math.min(tick * STEP, maxFlight)
    local highError = required(high)
    if lowError * highError <= 0 then
      local left, right, error = low, high, lowError
      for _ = 1, 20 do
        local mid = (left + right) * 0.5
        local value = required(mid)
        if error * value <= 0 then
          right = mid
        else
          left, error = mid, value
        end
      end
      local duration = (left + right) * 0.5
      local _, velocity = required(duration)
      local direction = velocity.Unit
      if clear(origin, direction * speed, gravity, drag, duration, destination, params) then
        return direction, duration
      end
    end
    low, lowError = high, highError
  end
  return nil
end
local function boxFraction(origin, delta, low, high)
  local near, far = 0, 1
  for _, axis in ipairs({ "X", "Y", "Z" }) do
    if math.abs(delta[axis]) < 1e-8 then
      if origin[axis] < low[axis] or origin[axis] > high[axis] then
        return nil
      end
    else
      local first, last = (low[axis] - origin[axis]) / delta[axis], (high[axis] - origin[axis]) / delta[axis]
      if first > last then
        first, last = last, first
      end
      near, far = math.max(near, first), math.min(far, last)
      if near > far then
        return nil
      end
    end
  end
  return near
end
local function actorHit(position, offset, actor, time, step, margin)
  local before, after = actor.predict(time), actor.predict(time + step)
  local crouch = actor.crouch and 0.3 or 0
  margin = margin or 0
  return boxFraction(
    position - before,
    offset - (after - before),
    Vector3.new(-0.3 + margin, -1.25 + margin, -0.3 + margin),
    Vector3.new(0.3 - margin, 0.71875 - crouch - margin, 0.3 - margin)
  )
end
local function hitsPlayer(origin, velocity, gravity, drag, duration, target, others, params, ownPosition, landingRadius)
  local position, time, contact = origin, 0, nil
  for _ = 1, math.ceil((duration + 0.5) / STEP) do
    local offset = velocity * STEP
    local hit = workspace:Raycast(units.toWorld(position), units.toWorld(offset), params)
    local fraction = actorHit(position, offset, target, time, STEP, 0.06)
    local solid = hit and hit.Distance / units.toWorld(offset.Magnitude) or math.huge
    for _, other in ipairs(others) do
      local earlier = actorHit(position, offset, other, time, STEP)
      if earlier and earlier < solid then
        return nil
      end
    end
    if not contact and fraction and fraction < solid then
      contact = time + STEP * fraction
    end
    if hit then
      if not contact then
        return nil
      end
      local impact, impactTime = units.toBlocks(hit.Position), time + STEP * solid
      local expected = target.predict(impactTime)
      local gap = impact - expected
      local radius = landingRadius or 1.25
      local height = -(gap.Y + 1.25)
      local validHeight = math.abs(height) <= 0.5
      if (gap * Vector3.new(1, 0, 1)).Magnitude > radius or not validHeight or (impact - ownPosition).Magnitude < 3 or not safeFloor(hit, impact, params) then
        return nil
      end
      return contact or impactTime, impact, impactTime
    end
    position += offset
    velocity = velocity * drag - Vector3.new(0, gravity * STEP, 0)
    time += STEP
  end
  return nil
end
function Ballistics.intercept(origin, target, others, speed, gravity, drag, inherited, params, maxFlight, ownPosition, landingRadius)
  local aimOffset = Vector3.new(0, -1.05, 0)
  local function required(time)
    local travel, drop = coefficients(time, drag)
    local destination = target.predict(time) + aimOffset
    local velocity = (destination - origin + Vector3.new(0, gravity * drop, 0)) / travel - inherited
    return velocity:Dot(velocity) - speed * speed, velocity
  end
  local low, previous = 0.001, required(0.001)
  for tick = 1, math.ceil(maxFlight / STEP) do
    local high = tick * STEP
    local error = required(high)
    if previous * error <= 0 then
      local left, right, sign = low, high, previous
      for _ = 1, 18 do
        local mid = (left + right) / 2
        local value = required(mid)
        if sign * value <= 0 then
          right = mid
        else
          left, sign = mid, value
        end
      end
      local duration = (left + right) / 2
      local _, velocity = required(duration)
      local direction = velocity.Unit
      local launchVelocity = direction * speed + inherited
      local contact, impact, impactTime = hitsPlayer(origin, launchVelocity, gravity, drag, duration, target, others, params, ownPosition, landingRadius)
      if contact then
        return {
          direction = direction,
          duration = impactTime,
          landing = impact,
          origin = origin,
        }
      end
    end
    low, previous = high, error
  end
  return nil
end
Ballistics.__contract =
  { provides = { "setup", "solve", "intercept" }, requires = { Units = "mcpunits" }, requiresMethods = { Units = { "toBlocks", "toWorld", "offset" } } }
return Ballistics
