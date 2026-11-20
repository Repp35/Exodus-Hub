-- [[ autospam ]]

-- code
local AutoSpam = {}
local utils, character, root
local active = false
local function setActive(value)
  active = value == true
  if utils then utils.setAutoSpamActive(active) end
end
function AutoSpam.setup(deps)
  if type(deps) ~= "table" or type(deps.Utils) ~= "table" then return false, "dependência ausente: Utils" end
  AutoSpam.teardown(); utils = deps.Utils
  setActive(false); return true
end
function AutoSpam.bindCharacter(value)
  AutoSpam.detachCharacter()
  if not utils then return false, "AutoSpam não inicializado" end
  local part = value and value:FindFirstChild("HumanoidRootPart")
  if not part or not part:IsA("BasePart") then return false, "HumanoidRootPart indisponível" end
  character, root = value, part; return true
end
function AutoSpam.detachCharacter()
  setActive(false); character, root = nil, nil
end
function AutoSpam.teardown()
  AutoSpam.detachCharacter(); utils = nil
end
function AutoSpam.onBallSync(_data) end
function AutoSpam.onDefenseOpportunity(_snapshot) return false end
function AutoSpam.isActive() return active end
function AutoSpam.canSend() return active and utils ~= nil and utils.isActive() end
function AutoSpam.canSendManual()
  if not utils or not utils.isActive() or not utils.isManualSpamActive() or not character or not character.Parent or not root or not root.Parent then return false end
  local humanoid = character:FindFirstChildOfClass("Humanoid"); local health = humanoid and humanoid.Health
  return type(health) == "number" and health == health and health < math.huge and health > 0
end
function AutoSpam.stopSpam(_reason) setActive(false) end
function AutoSpam.getActivationContext() return { active = active, reason = character and "waiting" or "detached", partner = -1 } end
function AutoSpam.getStatus() return { active = active, phase = character and "idle" or "detached", gates = {} } end
function AutoSpam.hasClashPrediction() return false end
AutoSpam.__contract = {
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "isActive", "isManualSpamActive", "setAutoSpamActive" } },
  provides = {
    "setup",
    "bindCharacter",
    "detachCharacter",
    "teardown",
    "onBallSync",
    "onDefenseOpportunity",
    "isActive",
    "canSend",
    "canSendManual",
    "stopSpam",
    "getActivationContext",
    "getStatus",
    "hasClashPrediction",
  },
  onBallSync = true,
  bindCharacter = true,
}

return AutoSpam
