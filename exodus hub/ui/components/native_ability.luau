-- [[ native ability ]]
--!optimize 2
-- @modules uinativeability

local Ability = {}
local UIKit
function Ability.setup(deps)
  UIKit = deps.UIKit
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
    read = options.read,
    observe = options.observe,
    miniScale = options.miniScale,
  })
  local view = kit.Components.mini(original.Parent, {
    scaleKey = options.scaleKey,
    squareKey = options.squareKey,
    name = options.name,
    onText = "ON",
    offText = "OFF",
    onTextSize = 18,
    offTextSize = 16,
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
  requires = { UIKit = "uikit" },
  requiresMethods = { UIKit = { "create" } },
}
return Ability
