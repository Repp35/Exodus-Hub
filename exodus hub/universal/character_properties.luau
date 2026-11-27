-- [[ character properties ]]
--!optimize 2
-- @modules characterproperties

local Properties = {}
function Properties.setup() return true end
function Properties.create(utils, desired)
  local humanoid, originals, applied = nil, {}, {}
  local binding = {}
  local function restore()
    if humanoid and humanoid.Parent then
      for key, value in pairs(originals) do
        if humanoid[key] == applied[key] then
          humanoid[key] = value
        end
      end
    end
    humanoid = nil
    table.clear(originals)
    table.clear(applied)
  end
  function binding.update()
    local player = utils.getLocalPlayer()
    local character = player and player.Character
    local target = character and character:FindFirstChildOfClass("Humanoid")
    if target and (not target.Parent or target.Health <= 0) then
      target = nil
    end
    if target ~= humanoid then
      restore()
      humanoid = target
    end
    if not humanoid then
      return
    end
    local values = desired(humanoid, originals)
    for key, value in pairs(values) do
      local current = humanoid[key]
      if applied[key] == nil or current ~= applied[key] then
        originals[key] = current
      end
      applied[key] = value
      if current ~= value then
        humanoid[key] = value
      end
    end
    for key, value in pairs(originals) do
      if values[key] == nil then
        if humanoid[key] == applied[key] then
          humanoid[key] = value
        end
        originals[key], applied[key] = nil, nil
      end
    end
  end
  function binding.restore() restore() end
  return binding
end
Properties.__contract = { access = { default = "lifetime.manage" }, provides = { "setup", "create" }, requires = {} }
return Properties
