-- [[ telemetry ]]

-- module
local Controller = {}

-- configuration
local CONFIG = { UPDATE_INTERVAL = 1 / 20 }

-- setup
function Controller.setup() return true end

-- controller
function Controller.create(context)
  local playerGui = context.playerGui; local Utils = context.deps.Utils
  local StatusView = context.deps.StatusView; local C = context.theme.COLORS
  local RunService = context.services.RunService; local inst = context.inst
  local corner = context.corner; local twPlay = context.twPlay
  local setTextIfChanged = context.setTextIfChanged; local trackConn = context.trackConn
  local untrackConn = context.untrackConn; local safeDisconnect = context.safeDisconnect
  context.refs.informationGui = inst("ScreenGui", {
    Name = "ExodusInformationOverlay",
    DisplayOrder = 2147483647,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Global,
    Parent = playerGui,
  })
  context.refs.toastLayer = inst("Frame", {
    Name = "ExodusToastLayer",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    ZIndex = 199,
    Parent = context.refs.informationGui,
  })
  return {}
end
Controller.__contract = { provides = { "setup", "create" }, requires = {} }

return Controller
