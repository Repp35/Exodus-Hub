-- [[ mm2 native ]]
--!optimize 2

local Native = {}
local Utils
local service, source, pending
local Input = game:GetService("UserInputService")
local function clientOf(tool, script) return typeof(script) == "Instance" and script:IsA("LocalScript") and script:IsDescendantOf(tool) end
local function valid(job)
  return Utils.isActive()
    and Utils.getLocalPlayer().Character == job.character
    and job.tool.Parent == job.character
    and job.tool.Enabled
    and job.tool:GetAttribute("Disabled") ~= true
    and job.humanoid.Parent
    and job.humanoid.Health > 0
    and (not job.allowed or job.allowed())
end
function Native.setup(deps)
  Native.teardown()
  Utils = deps.Utils
  return true
end
function Native.reset()
  local job = pending
  pending = nil
  if not job then
    return
  end
  for name, patch in pairs(job.patches) do
    if job.service[name] == patch.wrapper then
      job.service[name] = patch.original
    end
  end
  if job.action then
    pcall(function() job.action:Fire(false) end)
  end
  if job.kind == "throw" and not job.aimed and job.tool.Parent == job.character and job.humanoid.Parent then
    job.humanoid:UnequipTools()
  end
end
function Native.teardown()
  Native.reset()
  service, source = nil, nil
end
function Native.busy() return pending ~= nil end
local function weaponService()
  local folder = game:GetService("ReplicatedStorage"):FindFirstChild("ClientServices")
  local current = folder and folder:FindFirstChild("WeaponService")
  if current ~= source then
    service, source = nil, current
  end
  if not current or not current:IsA("ModuleScript") then
    return
  end
  if not service then
    local ok, value = pcall(require, current)
    if ok and type(value) == "table" then
      service = value
    end
  end
  return service
end
local function touchCallbacks(tool)
  local env = type(getgenv) == "function" and getgenv() or _G
  if type(env.getconnections) ~= "function" then
    return
  end
  local ok, connections = pcall(env.getconnections, Input.TouchTapInWorld)
  if not ok or type(connections) ~= "table" then
    return
  end
  local result = {}
  for _, connection in pairs(connections) do
    local readable, callback, enabled = pcall(function() return connection.Function, connection.Enabled end)
    if not readable or type(callback) ~= "function" or enabled == false then
      continue
    end
    local scoped, environment = pcall(getfenv, callback)
    if scoped and environment and clientOf(tool, environment.script) then
      result[#result + 1] = callback
    end
  end
  return #result > 0 and result or nil
end
local function throwAction()
  local gui = Utils.getLocalPlayer():FindFirstChildOfClass("PlayerGui")
  local context = gui and gui:FindFirstChild("InputContext")
  local gameplay = context and context:FindFirstChild("GameplayContext")
  local action = gameplay and gameplay:FindFirstChild("Throw")
  return action and action:IsA("InputAction") and action
end
local function mount(job)
  for _, name in ipairs({ "GetMouseTargetCFrame", "GetTargetPosition" }) do
    local original = job.service[name]
    if type(original) ~= "function" then
      return false
    end
    local function wrapper(self, ...)
      local caller = getfenv(2).script
      if pending == job and valid(job) and clientOf(job.tool, caller) then
        job.aimed = true
        return job.target
      end
      return original(self, ...)
    end
    job.patches[name] = { original = original, wrapper = wrapper }
    local ok = pcall(function() job.service[name] = wrapper end)
    if not ok or job.service[name] ~= wrapper then
      return false
    end
  end
  return true
end
function Native.stab(snap, tool, allowed)
  if pending or not tool or not tool:IsA("Tool") then
    return false
  end
  local job = { tool = tool, character = snap.character, humanoid = snap.humanoid, allowed = allowed }
  if not valid(job) then
    return false
  end
  local ok, reason = pcall(function() tool:Activate() end)
  return ok, not ok and tostring(reason) or nil
end
function Native.throw(snap, tool, target, allowed)
  if pending then
    return false, "Aguarde a ação nativa terminar."
  end
  if typeof(target) ~= "CFrame" or not tool or not tool:IsA("Tool") then
    return false, "Arma ou alvo indisponível."
  end
  local api = weaponService()
  if not api then
    return false, "WeaponService nativo indisponível."
  end
  local action, callbacks = throwAction(), touchCallbacks(tool)
  if not action or not callbacks then
    return false, "O controle nativo de lançamento não está acessível neste executor."
  end
  local charge = tonumber(tool:GetAttribute("ThrowSpeed"))
  if not charge or charge ~= charge or charge < 0 or charge > 10 then
    return false, "Tempo nativo de lançamento indisponível."
  end
  local now = os.clock()
  local job = {
    kind = "throw",
    tool = tool,
    character = snap.character,
    humanoid = snap.humanoid,
    service = api,
    patches = {},
    target = target,
    allowed = allowed,
    action = action,
    callbacks = callbacks,
    confirmAt = now + charge,
    expires = now + charge + 1,
  }
  if not valid(job) then
    return false, "A arma nativa não está pronta."
  end
  pending = job
  if not mount(job) then
    Native.reset()
    return false, "A mira nativa do MM2 não pôde ser conectada."
  end
  local ok, reason = pcall(function()
    action:Fire(true)
    action:Fire(false)
  end)
  if not ok then
    Native.reset()
    return false, tostring(reason)
  end
  return true
end
function Native.step()
  local job = pending
  if not job then
    return
  end
  if not valid(job) or os.clock() >= job.expires then
    Native.reset()
    return
  end
  for name, patch in pairs(job.patches) do
    if job.service[name] ~= patch.wrapper then
      Native.reset()
      return
    end
  end
  if job.aimed then
    Native.reset()
    return
  end
  if job.kind ~= "throw" or os.clock() < job.confirmAt then
    return
  end
  local camera = workspace.CurrentCamera
  if not camera then
    Native.reset()
    return
  end
  local point = camera.ViewportSize / 2
  for _, callback in ipairs(job.callbacks) do
    if pending ~= job or job.aimed then
      break
    end
    local ok, reason = pcall(callback, point, false)
    if not ok then
      Native.reset()
      Utils.recordError("mm2.native.throw", tostring(reason))
      return
    end
  end
end
Native.__contract = {
  provides = { "setup", "reset", "teardown", "busy", "stab", "throw", "step" },
  requires = { Utils = "utils" },
  requiresMethods = { Utils = { "isActive", "getLocalPlayer", "recordError" } },
}
return Native
