-- [[ mcp bridge ]]
--!optimize 2
local Bridge = {}
local utils, owner, nextScan = nil, nil, 0
local functions = {}
local names = {
  VoxelCombatClient = { performAttack = "attack" },
  ItemClient = { use = "use" },
  VoxelPackHUD = { refreshTools = "refresh", setOpen = "open", selectSlot = "select" },
}
function Bridge.setup(deps)
  utils = deps.Utils
  return true
end
local function inputFunction(key, scripts, env)
  if type(env.getconnections) ~= "function" then
    return nil
  end
  local source = game:GetService("ReplicatedStorage"):FindFirstChild("ControllerInput")
  local ok, controller = pcall(function() return source and require(source) end)
  if not ok or type(controller) ~= "table" or not controller.InputBegan then
    return nil
  end
  local connected, connections = pcall(env.getconnections, controller.InputBegan)
  if not connected or type(connections) ~= "table" then
    return nil
  end
  for _, connection in pairs(connections) do
    local readable, listener = pcall(function() return connection.Function end)
    if not readable or type(listener) ~= "function" then
      continue
    end
    local scoped, environment = pcall(getfenv, listener)
    local script = scoped and environment and environment.script
    if typeof(script) ~= "Instance" or script.Parent ~= scripts or not names[script.Name] then
      continue
    end
    local values = Bridge.upvalues(listener)
    if values then
      for _, fn in pairs(values) do
        if type(fn) ~= "function" then
          continue
        end
        local named, name = pcall(debug.info, fn, "n")
        if named and names[script.Name][name] == key then
          return { fn = fn, source = script }
        end
      end
    end
  end
  return nil
end
function Bridge.get(key)
  local scripts = utils.getLocalPlayer():FindFirstChild("PlayerScripts")
  if scripts ~= owner then
    owner, functions, nextScan = scripts, {}, 0
  end
  local cached = functions[key]
  if cached and cached.source.Parent == scripts then
    return cached.fn
  end
  local env = type(getgenv) == "function" and getgenv() or _G
  if not scripts then
    return nil
  end
  local linked = inputFunction(key, scripts, env)
  if linked then
    functions[key] = linked
    return linked.fn
  end
  if os.clock() < nextScan or type(env.getgc) ~= "function" then
    return nil
  end
  nextScan = os.clock() + 1
  local ok, objects = pcall(env.getgc, false)
  if not ok or type(objects) ~= "table" then
    return nil
  end
  local candidates, references = {}, {}
  for _, fn in pairs(objects) do
    if type(fn) ~= "function" then
      continue
    end
    local success, environment = pcall(getfenv, fn)
    local source = success and environment and environment.script
    if typeof(source) ~= "Instance" or source.Parent ~= scripts or not names[source.Name] then
      continue
    end
    local values = Bridge.upvalues(fn)
    if values then
      for _, value in pairs(values) do
        if type(value) == "function" then
          references[value] = (references[value] or 0) + 1
        end
      end
    end
    local named, name = pcall(debug.info, fn, "n")
    local field = named and names[source.Name][name]
    if field then
      candidates[#candidates + 1] = { key = field, fn = fn, source = source }
    end
  end
  for _, entry in ipairs(candidates) do
    local current = functions[entry.key]
    if not current or current.source.Parent ~= scripts or (references[entry.fn] or 0) > (references[current.fn] or 0) then
      functions[entry.key] = entry
    end
  end
  return functions[key] and functions[key].fn
end
function Bridge.upvalues(fn)
  local env = type(getgenv) == "function" and getgenv() or _G
  local getter = env.getupvalues or env.debug and env.debug.getupvalues
  if not fn or type(getter) ~= "function" then
    return nil
  end
  local ok, values = pcall(getter, fn)
  return ok and type(values) == "table" and values or nil
end
function Bridge.teardown()
  owner, functions, nextScan = nil, {}, 0
end
Bridge.__contract =
  { provides = { "setup", "get", "upvalues", "teardown" }, requires = { Utils = "utils" }, requiresMethods = { Utils = { "getLocalPlayer" } } }
return Bridge
