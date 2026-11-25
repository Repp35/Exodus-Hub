-- [[ mcpballistics ]]
--!optimize 2
local Ballistics = {}
function Ballistics.setup() return true end
-- ItemClient.advance: move for 0.05 s, then drag, then gravity.
local function heightAt(distance, speed, gravity, drag, pitch)
  local horizontal, vertical = speed * math.cos(pitch), speed * math.sin(pitch)
  local x, y, time = 0, 0, 0
  for _ = 1, 160 do
    local dx, dy = horizontal * 0.05, vertical * 0.05
    if dx <= 0.0001 then return nil end
    if x + dx >= distance then
      local fraction = (distance - x) / dx
      return y + dy * fraction, time + 0.05 * fraction
    end
    x, y, time = x + dx, y + dy, time + 0.05
    horizontal, vertical = horizontal * drag, vertical * drag - gravity * 0.05
  end
  return nil
end
local function clear(origin, direction, speed, gravity, drag, duration, destination, params)
  local position, velocity, elapsed = origin, direction * speed, 0
  -- A valid plan must end in a real floor collision, not just cross a point in mid-air.
  while elapsed < math.min(duration + 0.2, 0.9) do
    local step = math.min(0.05, math.min(duration + 0.2, 0.9) - elapsed)
    local offset = velocity * step
    local hit = workspace:Raycast(position, offset, params)
    if hit then
      if hit.Normal.Y < 0.65 or (hit.Position - destination).Magnitude > 1.2 then return false end
      local feet = hit.Position + Vector3.new(0, 0.1, 0)
      if workspace:Raycast(feet, Vector3.new(0, 6.4, 0), params) then return false end
      for _, offset2 in ipairs({ Vector3.new(0.65, 0, 0), Vector3.new(-0.65, 0, 0), Vector3.new(0, 0, 0.65), Vector3.new(0, 0, -0.65) }) do
        local floor = workspace:Raycast(feet + offset2 + Vector3.new(0, 0.3, 0), Vector3.new(0, -0.8, 0), params)
        if not floor or floor.Normal.Y < 0.65 then return false end
      end
      return true
    end
    position, elapsed = position + offset, elapsed + step
    velocity = velocity * drag - Vector3.new(0, gravity * 0.05, 0)
  end
  return false
end
function Ballistics.solve(origin, destination, speed, gravity, params)
  local delta = destination - origin
  local horizontal = Vector3.new(delta.X, 0, delta.Z)
  local distance, drag = horizontal.Magnitude, 0.99
  if distance < 0.01 or speed <= 0 or gravity <= 0 then return nil end
  local previousPitch, previousError
  for degrees = -85, 85 do
    local pitch = math.rad(degrees)
    local height = heightAt(distance, speed, gravity, drag, pitch)
    if height == nil then previousPitch, previousError = nil, nil continue end
    local error = height - delta.Y
    if previousError and previousError * error <= 0 then
      local lo, hi, lowError = previousPitch, pitch, previousError
      for _ = 1, 14 do
        local mid = (lo + hi) / 2
        local midHeight = heightAt(distance, speed, gravity, drag, mid)
        if not midHeight then break end
        local midError = midHeight - delta.Y
        if lowError * midError <= 0 then hi = mid else lo, lowError = mid, midError end
      end
      local angle = (lo + hi) / 2
      local _, duration = heightAt(distance, speed, gravity, drag, angle)
      local direction = horizontal.Unit * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)
      if duration and duration <= 0.75 and clear(origin, direction, speed, gravity, drag, duration, destination, params) then return direction, duration end
    end
    previousPitch, previousError = pitch, error
  end
  return nil
end
Ballistics.__contract = { provides = { "setup", "solve" }, requires = {} }
return Ballistics
