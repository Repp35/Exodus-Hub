-- [[ property binding ]]
--!optimize 2
-- @modules propertybinding

local Binding = {}
function Binding.setup() return true end
function Binding.create(resolve, desired)
  local target, originals, applied = nil, {}, {}
  local binding = {}
  local function restore()
    if target then
      for key, value in pairs(originals) do
        pcall(function()
          if target[key] == applied[key] then
            target[key] = value
          end
        end)
      end
    end
    target = nil
    table.clear(originals)
    table.clear(applied)
  end
  function binding.update()
    local nextTarget = resolve()
    if nextTarget ~= target then
      restore()
      target = nextTarget
    end
    if not target then
      return
    end
    local values = desired(target)
    for key, value in pairs(values) do
      local current = target[key]
      if applied[key] == nil or current ~= applied[key] then
        originals[key] = current
      end
      applied[key] = value
      if current ~= value then
        target[key] = value
      end
    end
    for key, value in pairs(originals) do
      if values[key] == nil then
        if target[key] == applied[key] then
          target[key] = value
        end
        originals[key], applied[key] = nil, nil
      end
    end
  end
  function binding.restore() restore() end
  return binding
end
Binding.__contract = { access = { default = "lifetime.manage" }, provides = { "setup", "create" }, requires = {} }
return Binding
