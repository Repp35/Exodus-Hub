-- [[ mini panels ]]
--!optimize 2
-- @modules uiminipanels

local Panels = {}
function Panels.setup() return true end
function Panels.create(context, definitions)
  local utils = context.deps.Utils
  for _, definition in ipairs(definitions or {}) do
    local dragging
    local handle = context.kit.Components.mini(context.refs.screenGui, {
      name = definition.name,
      title = definition.title,
      text = definition.text,
      visible = false,
      draggable = false,
      onActivate = function()
        if dragging and dragging() then
          return
        end
        local action = context.deps.Controls[definition.action]
        if action then
          action()
        end
      end,
    })
    local function refresh()
      handle.setAppearance(
        definition.scaleKey and utils.getConfigValue(definition.scaleKey) or 1,
        definition.squareKey and utils.getConfigValue(definition.squareKey) == true
      )
      local view = context.viewport()
      local scale = math.max(0.01, context.refs.responsiveScale.Scale)
      local width, height = handle.Root.Size.X.Offset, handle.Root.Size.Y.Offset
      handle.Root.Position = UDim2.fromOffset(
        math.clamp(utils.getConfigValue(definition.xKey) or (view.X / scale - width - 14), 0, math.max(0, view.X / scale - width)),
        math.clamp(utils.getConfigValue(definition.yKey) or (view.Y / scale / 2), 0, math.max(0, view.Y / scale - height))
      )
      handle.setVisible(utils.getConfigValue(definition.visibleKey) == true and (not definition.mobileOnly or not context.state.desktop))
      local invisible = definition.invisibleKey and utils.getConfigValue(definition.invisibleKey) == true
      handle.setInvisible(invisible)
    end
    dragging = context.makeDraggable(
      handle.Header,
      handle.Root,
      function() utils.setConfig({ [definition.xKey] = handle.Root.Position.X.Offset, [definition.yKey] = handle.Root.Position.Y.Offset }) end
    )
    handle.scope.add(utils.observeConfig(refresh))
    handle.scope.connect(context.refs.responsiveScale:GetPropertyChangedSignal("Scale"), refresh)
    refresh()
  end
  return {}
end
Panels.__contract = { provides = { "setup", "create" }, requires = {} }
return Panels
