-- [[ floating ]]

-- code
local Controller = {}
function Controller.setup() return true end
function Controller.create()
  local function inactive() end
  return {
    setSpam = inactive,
    showMini = inactive,
    applyMiniScale = inactive,
    showClashBall = inactive,
    showParryBall = inactive,
    showDarkBall = inactive,
    showJumpBall = inactive,
    showUpDashBall = inactive,
    sync = inactive,
    refreshAbilities = inactive,
  }
end
Controller.__contract = { provides = { "setup", "create" }, requires = {} }

return Controller
