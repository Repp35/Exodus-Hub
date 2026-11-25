-- [[ mcpballistics ]]
--!optimize 2
local Ballistics = {}
function Ballistics.setup() return true end
-- ItemClient.advance: move for 0.05 s, then drag, then gravity.
local function heightAt(distance, speed, gravity, drag, pitch)
  local horizontal, vertical = speed * math.cos(pitch), speed * math.sin(pitch)
  local step = 0.05
  if horizontal <= 0.0001 then
    return nil
  end
  local ticks, travel, height, vx, vy
  if math.abs(1 - drag) < 0.000001 then
    ticks = math.floor(distance / (horizontal * step))
    travel = horizontal * step * ticks
    height = vertical * step * ticks - gravity * step * step * ticks * (ticks - 1) / 2
    vx, vy = horizontal, vertical - gravity * step * ticks
  else
    local remaining = 1 - distance * (1 - drag) / (horizontal * step)
    if remaining <= 0 then
      return nil
    end
    ticks = math.floor(math.log(remaining) / math.log(drag))
    local decay = drag ^ ticks
    local sum = (1 - decay) / (1 - drag)
    local terminal = gravity * step / (1 - drag)
    travel = horizontal * step * sum
    height = step * ((vertical + terminal) * sum - terminal * ticks)
    vx, vy = horizontal * decay, (vertical + terminal) * decay - terminal
  end
  if ticks >= 160 or vx <= 0.0001 then
    return nil
  end
  local fraction = math.clamp((distance - travel) / (vx * step), 0, 1)
  return height + vy * step * fraction, (ticks + fraction) * step
end
local function clear(origin, direction, speed, gravity, drag, duration, destination, params, maxFlight)
  local position, velocity, elapsed = origin, direction * speed, 0
  -- A valid plan must end in a real floor collision, not just cross a point in mid-air.
  while elapsed < math.min(duration + 0.2, maxFlight + 0.2) do
    local step = math.min(0.05, math.min(duration + 0.2, maxFlight + 0.2) - elapsed)
    local offset = velocity * step
    local hit = workspace:Raycast(position, offset, params)
    if hit then
      local block = hit.Instance:GetAttribute("BlockKey")
      if hit.Material == Enum.Material.Water or block == "lava" or block == "water" then
        return false
      end
      if hit.Normal.Y < 0.65 or (hit.Position - destination).Magnitude > 1.2 then
        return false
      end
      local feet = hit.Position + Vector3.new(0, 0.1, 0)
      if workspace:Raycast(feet, Vector3.new(0, 6.4, 0), params) then
        return false
      end
      for _, offset2 in ipairs({ Vector3.new(0.65, 0, 0), Vector3.new(-0.65, 0, 0), Vector3.new(0, 0, 0.65), Vector3.new(0, 0, -0.65) }) do
        local floor = workspace:Raycast(feet + offset2 + Vector3.new(0, 0.3, 0), Vector3.new(0, -0.8, 0), params)
        if not floor or floor.Normal.Y < 0.65 then
          return false
        end
      end
      return true
    end
    position, elapsed = position + offset, elapsed + step
    velocity = velocity * drag - Vector3.new(0, gravity * 0.05, 0)
  end
  return false
end
function Ballistics.solve(origin, destination, speed, gravity, params, maxFlight, projectileDrag)
  maxFlight = maxFlight or 0.75
  local delta = destination - origin
  local horizontal = Vector3.new(delta.X, 0, delta.Z)
  local distance, drag = horizontal.Magnitude, projectileDrag or 0.99
  if distance < 0.01 or speed <= 0 or gravity <= 0 or drag <= 0 or drag > 1 then
    return nil
  end
  local previousPitch, previousError
  for degrees = -85, 85, 0.5 do
    local pitch = math.rad(degrees)
    local height = heightAt(distance, speed, gravity, drag, pitch)
    if height == nil then
      previousPitch, previousError = nil, nil
      continue
    end
    local error = height - delta.Y
    if previousError and previousError * error <= 0 then
      local lo, hi, lowError = previousPitch, pitch, previousError
      for _ = 1, 18 do
        local mid = (lo + hi) / 2
        local midHeight = heightAt(distance, speed, gravity, drag, mid)
        if not midHeight then
          break
        end
        local midError = midHeight - delta.Y
        if lowError * midError <= 0 then
          hi = mid
        else
          lo, lowError = mid, midError
        end
      end
      local angle = (lo + hi) / 2
      local _, duration = heightAt(distance, speed, gravity, drag, angle)
      local direction = horizontal.Unit * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)
      if duration and duration <= maxFlight and clear(origin, direction, speed, gravity, drag, duration, destination, params, maxFlight) then
        return direction, duration
      end
    end
    previousPitch, previousError = pitch, error
  end
  return nil
end
Ballistics.__contract = { provides = { "setup", "solve" }, requires = {} }
return Ballistics
