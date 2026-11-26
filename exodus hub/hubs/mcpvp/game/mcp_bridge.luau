-- [[ mcpbridge ]]
--!optimize 2
local Bridge = {}
local utils, scripts, nextScan = nil, nil, 0
local found = {}
local wanted = {
  VoxelCombatClient = { performAttack = "attack" },
  ItemClient = { use = "use" },
  VoxelPackHUD = { selectSlot = "select", refreshTools = "refresh", setOpen = "open" },
}
function Bridge.setup(deps)
  utils = deps.Utils
  return true
end
function Bridge.get(key)
  local current = utils.getLocalPlayer():FindFirstChild("PlayerScripts")
  if scripts ~= current then
    scripts, found, nextScan = current, {}, 0
  end
  local entry = found[key]
  if entry and entry.source.Parent == scripts then
    return entry.fn
  end
  if os.clock() < nextScan then
    return nil
  end
  nextScan = os.clock() + 5
  local env = type(getgenv) == "function" and getgenv() or _G
  if not scripts or type(env.getgc) ~= "function" then
    return nil
  end
  local ok, objects = pcall(env.getgc, false)
  if not ok or type(objects) ~= "table" then
    return nil
  end
  for _, fn in pairs(objects) do
    if type(fn) ~= "function" then
      continue
    end
    local got, scope = pcall(getfenv, fn)
    local source = got and scope and scope.script
    if typeof(source) ~= "Instance" or source.Parent ~= scripts then
      continue
    end
    local names = wanted[source.Name]
    if not names then
      continue
    end
    local named, name = pcall(debug.info, fn, "n")
    if named and names[name] then
      local key = names[name]
      local existing = found[key]
      -- Keep live call sites stable: executor hooks can expose an unhooked clone to getgc.
      if not existing or existing.source.Parent ~= scripts then
        found[key] = { fn = fn, source = source }
      end
    end
  end
  entry = found[key]
  return entry and entry.fn
end
function Bridge.upvalues(fn)
  local env = type(getgenv) == "function" and getgenv() or _G
  local getter = env.getupvalues or (env.debug and env.debug.getupvalues)
  if not fn or type(getter) ~= "function" then
    return nil
  end
  local ok, values = pcall(getter, fn)
  return ok and type(values) == "table" and values or nil
end
function Bridge.teardown()
  found, scripts, nextScan = {}, nil, 0
end
Bridge.__contract =
  { provides = { "setup", "get", "upvalues", "teardown" }, requires = { Utils = "utils" }, requiresMethods = { Utils = { "getLocalPlayer" } } }
return Bridge
