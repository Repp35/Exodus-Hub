-- [[ player registry ]]
--!optimize 2

-- code
local Registry = {}
local lifetime
local scope
local records = {}
local ordered = table.freeze({})
local function publish(player, added)
  local list = {}
  for _, candidate in ipairs(ordered) do
    if candidate ~= player then
      list[#list + 1] = candidate
    end
  end
  if added then
    list[#list + 1] = player
  end
  ordered = table.freeze(list)
end
function Registry.getPlayers() return ordered end
function Registry.getParts(id)
  local record = records[id]
  if not record then
    return nil
  end
  local player, character = record.player, record.character
  if player.Character ~= character or not character or not character.Parent then
    return player
  end
  local root, humanoid = record.root, record.humanoid
  return player, character, humanoid and humanoid.Parent == character and humanoid or nil, root and root.Parent == character and root or nil
end
function Registry.teardown()
  if scope then
    scope.destroy()
    scope = nil
  end
  table.clear(records)
  ordered = table.freeze({})
end
function Registry.setup(deps)
  Registry.teardown()
  lifetime = deps.Lifetime
  scope = lifetime.scope()
  local players = deps.Utils.getPlayers()
  local function remove(player)
    local record = records[player.UserId]
    if not record then
      return
    end
    record.scope.destroy()
    records[player.UserId] = nil
    publish(player, false)
  end
  local function add(player)
    if records[player.UserId] then
      return
    end
    local record = { player = player, scope = scope.child() }
    records[player.UserId] = record
    local function bind(character)
      if record.characterScope then
        record.characterScope.destroy()
      end
      record.character, record.root, record.humanoid = character, nil, nil
      if not character then
        return
      end
      local childScope = record.scope.child()
      record.characterScope = childScope
      local function added(child)
        if child.Name == "HumanoidRootPart" and child:IsA("BasePart") then
          record.root = child
        end
        if child:IsA("Humanoid") then
          record.humanoid = child
        end
      end
      childScope.connect(character.ChildAdded, added)
      childScope.connect(character.ChildRemoved, function(child)
        if record.root == child then
          record.root = nil
        end
        if record.humanoid == child then
          record.humanoid = nil
        end
      end)
      for _, child in ipairs(character:GetChildren()) do
        added(child)
      end
    end
    record.scope.connect(player.CharacterAdded, bind)
    record.scope.connect(player.CharacterRemoving, function(character)
      if character == record.character then
        bind(nil)
      end
    end)
    if player.Character then
      bind(player.Character)
    end
    publish(player, true)
  end
  scope.connect(players.PlayerAdded, add)
  scope.connect(players.PlayerRemoving, remove)
  for _, player in ipairs(players:GetPlayers()) do
    add(player)
  end
  return true
end
Registry.__contract = {
  requires = { Lifetime = "lifetime", Utils = "utils" },
  requiresMethods = { Lifetime = { "scope" }, Utils = { "getPlayers" } },
  provides = { "setup", "teardown", "getPlayers", "getParts" },
}

return Registry
