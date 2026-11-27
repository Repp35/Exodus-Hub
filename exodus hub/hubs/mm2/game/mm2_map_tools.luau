-- [[ mm2 map tools ]]
--!optimize 2

local MapTools = {}
local State, World, Movement, Utils
local manualUntil, nextVote = 0, 0
function MapTools.setup(deps)
  State, World, Movement, Utils = deps.State, deps.World, deps.Movement, deps.Utils
  return true
end
function MapTools.reset()
  manualUntil, nextVote = 0, 0
  Movement.cancel("manual")
  Movement.cancel("vote")
end
local function localSnap() return State.live(Utils.getLocalPlayer(), State.map() ~= nil) end
local function move(point, walking)
  local snap = localSnap()
  if not snap or not point then
    return false, "Destino ou personagem indisponível."
  end
  manualUntil = os.clock() + 12
  if walking then
    return Movement.walk(snap, point, "manual")
  end
  return Movement.teleport(snap, point)
end
function MapTools.map()
  local map = State.map()
  local spawns = map and map:FindFirstChild("Spawns")
  local spawn = spawns and spawns:FindFirstChildWhichIsA("BasePart", true)
  return move(spawn and spawn.Position + Vector3.new(0, 3, 0))
end
function MapTools.lobby()
  local lobby = workspace:FindFirstChild("RegularLobby")
  local spawn
  for _, name in ipairs({ "Spawn", "SpawnLocation", "LobbySpawn" }) do
    local candidate = lobby and lobby:FindFirstChild(name, true)
    if candidate and candidate:IsA("BasePart") then
      spawn = candidate
      break
    end
  end
  spawn = spawn or lobby and lobby:FindFirstChildWhichIsA("SpawnLocation", true)
  return move(spawn and spawn.Position + Vector3.new(0, 3, 0))
end
function MapTools.role(role)
  local target = State.findRole(role)
  return move(target and target.root.Position + Vector3.new(0, 0, 3))
end
function MapTools.gun()
  local snap = localSnap()
  local map = State.map()
  local _, point = World.nearest(snap and snap.root.Position or Vector3.zero, World.guns(), function(object) return map and object:IsDescendantOf(map) end)
  return move(point and point + Vector3.new(0, 2, 0))
end
function MapTools.holder()
  for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    local snap = State.live(player, true)
    if snap and player ~= Utils.getLocalPlayer() and State.tool(snap, "Gun", false) then
      return move(snap.root.Position + Vector3.new(0, 0, 3))
    end
  end
  return false, "Nenhum portador de arma disponível."
end
function MapTools.player(walking)
  local player = game:GetService("Players"):FindFirstChild(Utils.getConfigValue("MM2TargetPlayer") or "")
  local target = player ~= Utils.getLocalPlayer() and State.live(player, State.map() ~= nil)
  return move(target and target.root.Position + Vector3.new(0, 0, 3), walking)
end
function MapTools.players()
  local choices = { "None" }
  for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    if player ~= Utils.getLocalPlayer() then
      choices[#choices + 1] = player.Name
    end
  end
  table.sort(choices)
  return choices
end
local function board()
  local lobby = workspace:FindFirstChild("RegularLobby")
  local pads = lobby and lobby:FindFirstChild("VotePads")
  local entries = {}
  for index = 1, 3 do
    local pad = lobby and lobby:FindFirstChild("VotePad" .. index)
    local detector = pads and pads:FindFirstChild("Detector" .. index)
    if pad and detector and detector:IsA("BasePart") then
      local label = pad:FindFirstChild("MapName", true)
      if label and label:IsA("TextLabel") and label.Text ~= "" and label.Text ~= "MAP NAME" then
        entries[#entries + 1] = { name = label.Text, point = detector.Position }
      end
    end
  end
  return entries
end
function MapTools.maps()
  local choices = { "None" }
  local sync = game:GetService("ReplicatedStorage"):FindFirstChild("Database")
  sync = sync and sync:FindFirstChild("Sync")
  local maps = sync and sync:FindFirstChild("Maps")
  if maps and maps:IsA("ModuleScript") then
    local ok, result = pcall(require, maps)
    if ok and type(result) == "table" then
      for name in pairs(result) do
        if type(name) == "string" then
          choices[#choices + 1] = name
        end
      end
    end
  end
  if #choices == 1 then
    for _, entry in ipairs(board()) do
      choices[#choices + 1] = entry.name
    end
  end
  return choices
end
function MapTools.step()
  if os.clock() < nextVote then
    return
  end
  nextVote = os.clock() + 2
  local favorite = Utils.getConfigValue("MM2FavoriteMap")
  if State.map() or os.clock() < manualUntil or not favorite or favorite == "None" then
    Movement.cancel("vote")
    return
  end
  local normalize = function(value) return string.lower(value):gsub("[%s_%-]", "") end
  for _, entry in ipairs(board()) do
    if normalize(entry.name) == normalize(favorite) then
      local snap = localSnap()
      if snap and (snap.root.Position - entry.point).Magnitude > 3 and not Movement.busy() then
        Movement.walk(snap, entry.point, "vote")
      end
      return
    end
  end
end
MapTools.__contract = {
  provides = { "setup", "reset", "map", "lobby", "role", "gun", "holder", "player", "players", "maps", "step" },
  requires = { State = "mm2state", World = "mm2world", Movement = "mm2movement", Utils = "utils" },
  requiresMethods = {
    State = { "live", "map", "findRole", "tool" },
    World = { "nearest", "guns" },
    Movement = { "walk", "teleport", "cancel", "busy" },
    Utils = { "getLocalPlayer", "getConfigValue" },
  },
}
return MapTools
