-- [[ native ability ]]
--!optimize 2
-- @modules uinativeability

local Ability = {}
local UIKit, Utils
function Ability.setup(deps)
  UIKit, Utils = deps.UIKit, deps.Utils
  return true
end
function Ability.create(ability, options)
  options = options or {}
  local interface = ability and ability.Interface
  local original = interface and interface.MobileUIAbilityFrame
  if not original or not original.Parent then
    return nil
  end
  local kit = UIKit.create({
    parent = original.Parent,
    read = Utils.getConfigValue,
    observe = Utils.observeConfig,
  })
  local view = kit.Components.mini(original.Parent, {
    scaleKey = "MiniUIScale",
    squareKey = "MiniUISquare",
    name = options.name,
    text = "PARRY",
    visible = false,
    size = 64,
    position = original.Position,
    onPress = options.onPress,
  })
  view.Root.AnchorPoint = original.AnchorPoint
  local wasVisible = original.Visible
  original.Visible = false
  local handle = { original = original, clone = view.Root }
  function handle.setState(active, mobile)
    original.Visible = false
    view.setValue(active)
    view.setVisible(mobile)
  end
  function handle.destroy()
    kit.destroy()
    if original.Parent then
      original.Visible = wasVisible
    end
  end
  return handle
end
function Ability.reveal(ability)
  local frame = ability and ability.Interface and ability.Interface.MobileUIAbilityFrame
  if frame and frame.Parent then
    frame.Visible = true
  end
end
Ability.__contract = {
  access = { methods = { create = "ui.use", reveal = "ui.use" } },
  provides = { "setup", "create", "reveal" },
  requires = { UIKit = "uikit", Utils = "utils" },
  requiresMethods = { UIKit = { "create" }, Utils = { "getConfigValue", "observeConfig" } },
}
return Ability
