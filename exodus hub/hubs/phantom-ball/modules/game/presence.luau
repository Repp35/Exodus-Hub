-- [[ match presence tracking ]]

-- code
local Presence = {}
function Presence.setup() return true end
function Presence.create(utils, registry)
  local players, world = utils.getPlayers(), utils.getWorkspace(); local presence, presenceConnections, presenceDeath = {}, {}, nil
  local presenceHumanoid, lobbyRegion, lobbySearchAt
  local function finite(value) return utils.isFiniteNumber(value) end
  local function child(parent, name) return parent and parent:FindFirstChild(name) end
  local function inLobby(root)
    if not root then return true end
    local time = os.clock()
    if not lobbyRegion or not lobbyRegion.Parent then
      if not lobbySearchAt or time >= lobbySearchAt then lobbySearchAt = time + 0.5; lobbyRegion = world:FindFirstChild("Lobby Area", true) end
    end
    local function inside(region)
      if not region or not region:IsA("BasePart") then return false end
      local point = region.CFrame:PointToObjectSpace(root.Position); local half = region.Size * 0.5
      return math.abs(point.X) <= half.X and math.abs(point.Y) <= half.Y and math.abs(point.Z) <= half.Z
    end
    return inside(lobbyRegion) or inside(child(child(child(world, "Training"), "Areas"), "SafeArea"))
  end
  local function stopPresence()
    if presenceDeath then presenceDeath:Disconnect(); presenceDeath = nil end
    for _, connection in ipairs(presenceConnections) do
      if utils and type(utils.untrackGlobal) == "function" then utils.untrackGlobal(connection) end
      connection:Disconnect()
    end
    presenceConnections, presenceHumanoid, presence = {}, nil, {}
  end
  local function updatePresence()
    if not players or not world then return end
    local player = players.LocalPlayer; local _, character, humanoid, root = registry.getParts(player and player.UserId)
    local round = world:GetAttribute("MatchStatus") == 6; local lives = player and player:GetAttribute("Lives")
    local playing = player and player:GetAttribute("Playing")
    if humanoid ~= presenceHumanoid then
      if presenceDeath then presenceDeath:Disconnect(); presenceDeath = nil end
      presenceHumanoid = humanoid
      if humanoid and humanoid.Died then
        presenceDeath = humanoid.Died:Connect(function()
          if presenceHumanoid == humanoid and player.Character == character and world:GetAttribute("MatchStatus") == 6 then presence.eliminated, presence.entered = true, false end
        end)
      end
    end
    if presence.round == nil then presence.needsTeleport = not round end
    if not round then
      if presence.round == true then presence.entryProof = false end
      presence.eliminated, presence.entered, presence.needsTeleport = false, false, true
    elseif presence.round == true and presence.entered and presence.character and presence.character ~= character then
      presence.eliminated, presence.entered = true, false
    end
    if root and presence.position and (root.Position - presence.position).Magnitude >= 24 then presence.entryProof = true end
    local alive = humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root.Parent ~= nil
    if round and ((humanoid and humanoid.Health <= 0) or (finite(presence.lives) and presence.lives > 0 and finite(lives) and lives <= 0)) then presence.eliminated = true end
    local candidate = round and alive and finite(lives) and lives > 0 and playing ~= false and not inLobby(root)
    if presence.entered and not candidate then
      if not alive or playing == false or not finite(lives) or lives <= 0 then presence.eliminated = true end
      presence.needsTeleport, presence.entryProof = true, false
    end
    presence.entered = candidate and not presence.eliminated and (not presence.needsTeleport or presence.entryProof == true) or false
    presence.round, presence.character, presence.position, presence.lives = round, character, root and root.Position, lives
  end
  local function startPresence()
    presence, lobbyRegion, lobbySearchAt = {}, nil, nil; updatePresence()
    local function track(connection)
      presenceConnections[#presenceConnections + 1] = connection
      if type(utils.trackGlobal) == "function" then utils.trackGlobal(connection) end
    end
    if type(world.GetAttributeChangedSignal) == "function" then track(world:GetAttributeChangedSignal("MatchStatus"):Connect(updatePresence)) end
    local runService = type(utils.getRunService) == "function" and utils.getRunService()
    if runService and runService.Heartbeat then
      local elapsed = 0
      track(runService.Heartbeat:Connect(function(dt)
        elapsed += dt
        if elapsed >= 0.1 then elapsed = 0; updatePresence() end
      end))
    end
  end
  return { start = startPresence, stop = stopPresence, update = updatePresence, get = function() return presence, presenceHumanoid end }
end
Presence.__contract = { requires = {}, provides = { "setup", "create" } }

return Presence
