-- [[ registry ]]
--!strict
--!optimize 2

-- code
export type ModuleEntry = { name: string, path: string, hash: string? }
export type HubProfile = {
  id: string,
  title: string,
  version: string?,
  developers: { string }?,
  author: string?,
  notification: string?,
  placeIds: { number }?,
  universeIds: { number }?,
  modules: { ModuleEntry }?,
  permissions: boolean?,
  checkPermissions: boolean?,
  permissionPolicy: { [string]: any }?,
  dataFolder: string?,
}

export type Identity = { userId: number?, username: string? }
export type AccessRule = {
  mode: string?,
  userIds: { number }?,
  usernames: { string }?,
  blockedUserIds: { number }?,
  blockedUsernames: { string }?,
}
export type AccessPolicy = { exodus: AccessRule?, games: { [string]: AccessRule }? }
local function matches(ids: { number }?, names: { string }?, identity: Identity): boolean
  if identity.userId and table.find(ids or {}, identity.userId) then
    return true
  end
  local username = string.lower(identity.username or "")
  for _, name in ipairs(names or {}) do
    if username ~= "" and string.lower(name) == username then
      return true
    end
  end
  return false
end
local function allowed(rule: AccessRule?, identity: Identity): boolean
  if not rule then
    return true
  end
  if matches(rule.blockedUserIds, rule.blockedUsernames, identity) then
    return false
  end
  if rule.mode == "public" then
    return true
  end
  return rule.mode == "allowlist" and matches(rule.userIds, rule.usernames, identity)
end

local Registry = {}
function Registry.select(profiles: { HubProfile }, placeId: number, universeId: number?): HubProfile
  for _, profile in ipairs(profiles) do
    if table.find(profile.placeIds or {}, placeId) then
      return table.clone(profile)
    end
  end
  for _, profile in ipairs(profiles) do
    if universeId and universeId ~= 0 and table.find(profile.universeIds or {}, universeId) then
      return table.clone(profile)
    end
  end
  return {
    id = "universal",
    title = "Universal",
    author = "deltapolinha_2915",
    notification = "Universal carregado.",
  }
end
function Registry.resolve(profiles: { HubProfile }, placeId: number, universeId: number?, identity: Identity, access: AccessPolicy): (HubProfile?, string?)
  if not access.exodus or not allowed(access.exodus, identity) then
    return nil, "Conta sem acesso ao Exodus Hub"
  end
  local games = access.games or {}
  local profile = Registry.select(profiles, placeId, universeId)
  if not allowed(games[profile.id], identity) then
    profile = Registry.select({}, placeId, universeId)
  end
  if not allowed(games[profile.id], identity) then
    return nil, "Conta sem acesso ao Universal"
  end
  return profile, nil
end
function Registry.manifest(common: { ModuleEntry }, profile: HubProfile): { ModuleEntry }
  local entries: { ModuleEntry } = {}
  for _, entry in ipairs(common) do
    if entry.name ~= "permissions" or profile.permissions == true then
      entries[#entries + 1] = entry
    end
  end
  return Registry.merge(entries, profile.modules)
end
function Registry.merge(common: { ModuleEntry }, profile: { ModuleEntry }?): { ModuleEntry }
  local result: { ModuleEntry } = {}
  local positions: { [string]: number } = {}
  for _, entry in ipairs(common) do
    assert(type(entry.name) == "string" and not positions[entry.name], "Duplicate base module")
    positions[entry.name] = #result + 1
    result[#result + 1] = table.clone(entry)
  end
  local seen: { [string]: boolean } = {}
  for _, entry in ipairs(profile or {}) do
    assert(type(entry.name) == "string" and type(entry.path) == "string" and not seen[entry.name], "Invalid or duplicate hub module")
    assert(entry.path:match("^hubs/[%w%-]+/") and not entry.path:find("..", 1, true), "Invalid hub path")
    assert(entry.name ~= "permissions" and entry.name ~= "gamecontext" and entry.name ~= "hubapi", "Reserved base module")
    assert(not positions[entry.name], "Game module duplicates shared module: " .. entry.name)
    seen[entry.name] = true
    local index = positions[entry.name] or #result + 1
    positions[entry.name] = index
    result[index] = table.clone(entry)
  end
  return result
end

return Registry
