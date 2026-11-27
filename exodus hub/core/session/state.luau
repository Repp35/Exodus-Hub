--!optimize 2
-- @modules state

local State = {}
function State.setup() return true end
function State.create()
  return {
    active = false,
    config = {},
    urls = {},
    globalConnections = {},
    characterConnections = {},
    lifecycle = {
      phase = "stopped",
      generation = 0,
      startedAt = 0,
      stoppedAt = 0,
    },
    diagnostics = { errors = {}, transitions = {}, lastTransitionAt = 0 },
  }
end
local function copy(value, visited)
  if type(value) ~= "table" then
    return value
  end
  visited = visited or {}
  if visited[value] then
    return visited[value]
  end
  local result = {}
  visited[value] = result
  for key, item in pairs(value) do
    result[copy(key, visited)] = copy(item, visited)
  end
  return result
end
function State.copy(value) return copy(value) end
State.__contract = { requires = {}, provides = { "setup", "create", "copy" } }
return State
