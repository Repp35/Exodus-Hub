-- [[ Native lighting ownership for the local clock ]]
--!optimize 2
local PrisonLighting = {}
local binding, lifetime, scope
local active, writing = false, false
local lighting = game:GetService("Lighting")
local owner, native, applied = {}, {}, {}
local properties = {
  "Brightness",
  "Ambient",
  "OutdoorAmbient",
  "GlobalShadows",
  "ExposureCompensation",
  "EnvironmentDiffuseScale",
  "EnvironmentSpecularScale",
  "ColorShift_Top",
  "ColorShift_Bottom",
  "LightingStyle",
  "PrioritizeLightingQuality",
}
local function applyProperty(key, value)
  applied[key] = value
  local ok, reason = binding.apply(owner, lighting, key, value, 40)
  assert(ok, tostring(reason))
end
function PrisonLighting.start()
  if active then
    return
  end
  table.clear(native)
  table.clear(applied)
  scope = lifetime.scope()
  for _, key in ipairs(properties) do
    -- Read beneath Fullbright and AntiLag layers, including when they were
    -- enabled before this control. Do not bake their white ambient into time.
    local ok, value = pcall(binding.getOriginal, lighting, key)
    if not ok then
      continue
    end
    native[key] = value
    scope.connect(lighting:GetPropertyChangedSignal(key), function()
      local value = lighting[key]
      if not writing and value ~= applied[key] then
        native[key] = value
      end
    end)
  end
  active = true
end
function PrisonLighting.apply(minutes)
  if not active then
    return
  end
  writing = true
  for key, value in pairs(native) do
    applyProperty(key, value)
  end
  -- The clock participates in the same ownership system as Fullbright so
  -- neither its 14:00 override nor flat ambient can cancel night lighting.
  applyProperty("ClockTime", minutes / 60)
  writing = false
end
function PrisonLighting.stop(minutes)
  if not active then
    return
  end
  active = false
  scope.destroy()
  scope = nil
  for key, value in pairs(native) do
    binding.release(owner, lighting, key, value)
  end
  binding.release(owner, lighting, "ClockTime", minutes and minutes / 60)
  table.clear(native)
  table.clear(applied)
end
function PrisonLighting.setup(deps)
  binding, lifetime = deps.Binding, deps.Lifetime
  return true
end
function PrisonLighting.teardown()
  PrisonLighting.stop()
  return true
end
PrisonLighting.__contract = {
  requires = { Binding = "propertybinding", Lifetime = "lifetime" },
  requiresMethods = { Binding = { "getOriginal", "apply", "release" }, Lifetime = { "scope" } },
  provides = { "setup", "teardown", "start", "apply", "stop" },
}
return PrisonLighting
