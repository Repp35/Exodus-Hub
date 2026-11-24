-- [[ registry ]]

-- code
local Registry = {}
function Registry.select(profiles, placeId, universeId)
  for _, profile in ipairs(profiles) do
    if table.find(profile.placeIds or {}, placeId) then return table.clone(profile) end
  end
  for _, profile in ipairs(profiles) do
    if universeId and universeId ~= 0 and table.find(profile.universeIds or {}, universeId) then return table.clone(profile) end
  end
  return {
    id = "universal",
    title = "Universal",
    author = "deltapolinha_2915",
    notification = "Exodus Hub · Universal carregado. Este jogo ainda não tem integração própria.",
  }
end
function Registry.merge(common, profile)
  local result, positions = {}, {}
  for _, entry in ipairs(common) do
    assert(type(entry.name) == "string" and not positions[entry.name], "Duplicate base module"); positions[entry.name] = #result + 1
    result[#result + 1] = table.clone(entry)
  end
  local seen = {}
  for _, entry in ipairs(profile or {}) do
    assert(type(entry.name) == "string" and type(entry.path) == "string" and not seen[entry.name], "Invalid or duplicate hub module")
    assert(entry.path:match("^hubs/[%w%-]+/") and not entry.path:find("..", 1, true), "Invalid hub path")
    assert(entry.name ~= "permissions" and entry.name ~= "gamecontext" and entry.name ~= "hubapi", "Reserved base module"); seen[entry.name] = true
    local index = positions[entry.name] or #result + 1; positions[entry.name] = index
    result[index] = table.clone(entry)
  end
  return result
end

return Registry
