-- [[ mcpballistics ]]
--!optimize 2
local Ballistics = {}
function Ballistics.setup() return true end
-- Minecraft-equivalent defaults in tuning; the adapter can supply game values.
function Ballistics.solve(origin, destination, speed, gravity, params)
  local delta = destination - origin
  local horizontal = Vector3.new(delta.X, 0, delta.Z)
  local distance = horizontal.Magnitude
  if distance < 0.01 or speed <= 0 or gravity <= 0 then
    return nil
  end
  local square = speed * speed
  local discriminant = square * square - gravity * (gravity * distance * distance + 2 * delta.Y * square)
  if discriminant < 0 then
    return nil
  end
  for _, sign in ipairs({ -1, 1 }) do
    local tangent = (square + sign * math.sqrt(discriminant)) / (gravity * distance)
    local cosine = 1 / math.sqrt(1 + tangent * tangent)
    local velocity = horizontal.Unit * (speed * cosine) + Vector3.new(0, speed * cosine * tangent, 0)
    local duration = distance / (speed * cosine)
    local previous, clear = origin, true
    local steps = math.ceil(duration / 0.025)
    for step = 1, steps do
      local t = duration * step / steps
      local point = origin + velocity * t - Vector3.new(0, gravity * t * t / 2, 0)
      local hit = workspace:Raycast(previous, point - previous, params)
      if hit then
        if (hit.Position - destination).Magnitude > 4.8 then
          clear = false
        end
        break
      end
      previous = point
    end
    if clear then
      return velocity.Unit, duration
    end
  end
  return nil
end
Ballistics.__contract = { provides = { "setup", "solve" }, requires = {} }
return Ballistics
