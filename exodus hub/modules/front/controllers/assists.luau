-- [[ UI assistance preferences ]]

-- code
local Assists = {}
function Assists.setup() return true end
function Assists.create(context)
  if context.phantomBall == false then return {} end
  local utils, gameInfo = context.deps.Utils, context.deps.GameInfo; local players = context.services.Players
  local player = players.LocalPlayer
  local deathConnection, childConnection, currentCharacter
  local function clearCharacter()
    if deathConnection then deathConnection:Disconnect(); deathConnection = nil end
    if childConnection then childConnection:Disconnect(); childConnection = nil end
    currentCharacter = nil
  end
  local function watch(character)
    clearCharacter(); currentCharacter = character
    local function bind(humanoid)
      if currentCharacter ~= character or player.Character ~= character or deathConnection or not humanoid:IsA("Humanoid") then return end
      deathConnection = humanoid.Died:Connect(function()
        if
          currentCharacter == character
          and utils.isActive()
          and utils.getConfigValue("ParryOnDeath") == true
          and utils.getConfigValue("AutoParry") ~= true
        then
          utils.setConfig({ AutoParry = true })
        end
      end)
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then bind(humanoid) end
    childConnection = character.ChildAdded:Connect(bind)
  end
  context.trackConn(player.CharacterAdded:Connect(watch))
  context.trackConn(player.CharacterRemoving:Connect(function(character)
    if currentCharacter == character then clearCharacter() end
  end))
  if player.Character then watch(player.Character) end
  context.scope.add(clearCharacter); local elapsed, wasDuel = 0, false
  context.trackConn(context.services.RunService.Heartbeat:Connect(function(dt)
    elapsed += dt
    if elapsed < 0.25 then return end
    elapsed = 0; local duel = false
    if not context.state.desktop and utils.isActive() and utils.getConfigValue("ManualSpamUIOnDuel") == true then
      local match = gameInfo.getGameContext()
      if match.inMatch and match.alive and match.roundActive then
        local count = 0
        for _, candidate in ipairs(players:GetPlayers()) do
          local lives, model = candidate:GetAttribute("Lives"), candidate.Character; local humanoid = model and model:FindFirstChildOfClass("Humanoid")
          if type(lives) == "number" and lives > 0 and candidate:GetAttribute("Playing") ~= false and humanoid and humanoid.Health > 0 then count += 1 end
        end
        duel = count == 2
      end
    end
    if duel and not wasDuel and utils.getConfigValue("MiniSpamVisible") ~= true then context.setConfigValue("MiniSpamVisible", true) end
    wasDuel = duel
  end))
  return {}
end
Assists.__contract = { provides = { "setup", "create" }, requires = {} }

return Assists
