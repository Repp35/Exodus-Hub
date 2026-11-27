-- [[ reversible property ownership ]]
--!optimize 2
-- @modules propertybinding
local Binding = {}
local targets = setmetatable({}, { __mode = "k" })
local sequence = 0
function Binding.setup() return true end
function Binding.getOriginal(target, key)
  local properties = targets[target]
  local entry = properties and properties[key]
  if entry then
    return entry.original
  end
  return target[key]
end
local function winner(entry)
  local selected
  for _, layer in pairs(entry.layers) do
    if not selected or layer.priority > selected.priority or layer.priority == selected.priority and layer.order > selected.order then
      selected = layer
    end
  end
  return selected
end
function Binding.apply(owner, target, key, value, priority)
  local properties = targets[target]
  if not properties then
    properties = {}
    targets[target] = properties
  end
  local entry = properties[key]
  if not entry then
    entry = { original = target[key], layers = {} }
    properties[key] = entry
  end
  local layer = entry.layers[owner]
  if not layer then
    sequence += 1
    layer = { order = sequence }
    entry.layers[owner] = layer
  end
  layer.value, layer.priority = value, priority or 20
  local selected = winner(entry)
  return pcall(function()
    if target[key] ~= selected.value then
      target[key] = selected.value
    end
  end)
end
function Binding.release(owner, target, key, restoreValue)
  local properties = targets[target]
  local entry = properties and properties[key]
  if not entry or not entry.layers[owner] then
    return true
  end
  if restoreValue ~= nil then
    entry.original = restoreValue
  end
  entry.layers[owner] = nil
  local selected = winner(entry)
  local value = entry.original
  if selected then
    value = selected.value
  end
  local ok, reason = pcall(function() target[key] = value end)
  if not selected then
    properties[key] = nil
    if not next(properties) then
      targets[target] = nil
    end
  end
  return ok, reason
end
function Binding.create(resolve, desired)
  local target, originals, captured = nil, {}, {}
  local binding = {}
  local function release(key)
    local ok, reason = Binding.release(binding, target, key)
    if not ok and target and target.Parent ~= nil then
      warn("[Exodus] Restore " .. tostring(key) .. ": " .. tostring(reason))
    end
    originals[key], captured[key] = nil, nil
  end
  function binding.restore()
    if target then
      for key in pairs(captured) do
        release(key)
      end
    end
    target = nil
    table.clear(originals)
    table.clear(captured)
  end
  function binding.update()
    local nextTarget = resolve()
    if nextTarget ~= target then
      binding.restore()
      target = nextTarget
    end
    if not target then
      return
    end
    local values = desired(target, originals)
    for key, value in pairs(values) do
      if not captured[key] then
        local entry = targets[target] and targets[target][key]
        if entry then
          originals[key] = entry.original
        else
          originals[key] = target[key]
        end
        captured[key] = true
      end
      local ok, reason = Binding.apply(binding, target, key, value)
      assert(ok, tostring(reason))
    end
    for key in pairs(captured) do
      if values[key] == nil then
        release(key)
      end
    end
  end
  return binding
end
Binding.__contract = {
  access = { default = "property.write" },
  provides = { "setup", "create", "apply", "release", "getOriginal" },
  requires = {},
}
return Binding
