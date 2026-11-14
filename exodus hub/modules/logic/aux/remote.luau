-- [[ remote ]]

-- module
local Remote = {}
local gameInfo, utils
local epoch = 0
local keybindObject
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- configuration
local CONFIG = {
  PARRY_METHOD = "Deflect",
  DARK_METHOD = "SendEvent",
  FIERCE_METHOD = "ActivateAndBlock",
  DASH_METHOD = "Dash",
}

-- lifecycle
function Remote.setup(deps)
  if type(deps) ~= "table" or type(deps.GameInfo) ~= "table" then return false, "dependência inválida: GameInfo" end
  if type(deps.Utils) ~= "table" then return false, "dependência inválida: Utils" end
  Remote.teardown(); gameInfo, utils = deps.GameInfo, deps.Utils
  return true
end

-- dispatch
local function send(ability, method, ...)
  if ability == nil then return false, method .. " não equipado ou indisponível" end
  local callback = ability[method]
  if type(callback) ~= "function" then error("API externa ausente: habilidade." .. method, 2) end
  local result = callback(ability, ...)
  if result == false then return false, method .. " recusado" end
  return true
end
local function allowed(guard)
  if type(guard) ~= "function" then return true end
  local result = guard(); return result ~= nil and result ~= false
end
local directSequence = math.random(0, 65535)
local function directRemote()
  local env = type(getrenv) == "function" and getrenv() or nil; local globals = type(env) == "table" and rawget(env, "_G")
  local remote = type(globals) == "table" and rawget(globals, "did2") or nil
  if typeof(remote) == "Instance" and remote:IsA("RemoteEvent") then
    local unreliable = rawget(globals, "did2u")
    if typeof(unreliable) ~= "Instance" or not unreliable:IsA("UnreliableRemoteEvent") or unreliable.Parent ~= remote then unreliable = remote:FindFirstChild("u") end
    return remote, unreliable
  end
  local remotes = ReplicatedStorage:FindFirstChild("Remotes"); local player = Players.LocalPlayer
  remote = remotes and player and (remotes:FindFirstChild("pu_" .. player.UserId) or remotes:FindFirstChild(""))
  if remote and remote:IsA("RemoteEvent") then return remote, remote:FindFirstChild("u") end
end
local function fireDirect()
  local remote, unreliable = directRemote()
  if not remote then return false, "Remote de Deflect indisponível" end
  local camera = workspace.CurrentCamera
  if not camera then return false, "Câmera indisponível" end
  local cf = camera.CFrame
  local pos, look = cf.Position, cf.LookVector
  local packet = buffer.create(35); buffer.writeu8(packet, 0, 1)
  buffer.writef32(packet, 1, pos.X); buffer.writef32(packet, 5, pos.Y)
  buffer.writef32(packet, 9, pos.Z); buffer.writef32(packet, 13, look.X)
  buffer.writef32(packet, 17, look.Y); buffer.writef32(packet, 21, look.Z)
  directSequence = (directSequence + 1) % 65536; buffer.writeu16(packet, 25, directSequence)
  buffer.writef64(packet, 27, workspace:GetServerTimeNow()); remote:FireServer(packet)
  if unreliable and unreliable:IsA("UnreliableRemoteEvent") then
    unreliable:FireServer(packet); local owner = epoch
    task.delay(0.03, function()
      if epoch == owner and gameInfo and unreliable.Parent == remote and remote.Parent ~= nil then unreliable:FireServer(packet) end
    end)
  end
  return true
end
local function configuredInput()
  local ability = gameInfo.getDeflectAbility()
  if ability and type(ability.GetKeybindBySlotID) == "function" then
    local binding = ability:GetKeybindBySlotID()
    if binding then
      for index = 1, 2 do
        local value = index == 1 and binding.Key or binding.AlternateKey
        if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode and value ~= Enum.KeyCode.Unknown then return value end
      end
    end
  end
  if not keybindObject then
    local storage = ReplicatedStorage; local shared = storage:FindFirstChild("Shared") or storage:FindFirstChild("TS")
    local core = shared and shared:FindFirstChild("Core"); local module = core and core:FindFirstChild("KeybindObject")
    if module and module:IsA("ModuleScript") then
      local ok, value = pcall(require, module)
      if ok and type(value) == "table" and type(value.KeybindObject) == "table" then keybindObject = value.KeybindObject end
    end
  end
  if keybindObject and type(keybindObject.Get) == "function" then
    local binding = keybindObject:Get("Blocking")
    if binding then
      for index = 1, 2 do
        local value = index == 1 and binding.Key or binding.AlternateKey
        if typeof(value) == "EnumItem" and value ~= Enum.KeyCode.Unknown then
          if value.EnumType == Enum.KeyCode then return value end
        end
      end
    end
  end
  return Enum.KeyCode.F
end
local function fireInput()
  local input = configuredInput(); local vim = game:GetService("VirtualInputManager")
  vim:SendKeyEvent(true, input, false, game)
  task.defer(function() vim:SendKeyEvent(false, input, false, game) end)
  return true
end

-- public-api
function Remote.fireParry(_flag, guard)
  if not gameInfo then return false, "Remote não inicializado" end
  local method = utils.getConfigValue("ClickMethod")
  if method == "Input" then
    if not allowed(guard) then return false, "Deflect cancelado" end
    return fireInput()
  end
  if gameInfo.isTrainingArea() then
    if not allowed(guard) then return false, "Deflect cancelado" end
    local sent, detail = gameInfo.fireTrainingParry(); return sent, detail
  end
  if not allowed(guard) then return false, "Deflect cancelado" end
  if method == "Direct" then return fireDirect() end
  return send(gameInfo.getDeflectAbility(), CONFIG.PARRY_METHOD)
end
function Remote.fireDark(eventId, cameraFrame) return send(gameInfo and gameInfo.getDarkSealAbility(), CONFIG.DARK_METHOD, eventId, cameraFrame) end
function Remote.fireFierce(guard)
  local ability = gameInfo and gameInfo.getFierceDeflectAbility()
  if not allowed(guard) then return false, "Fierce cancelado" end
  return send(ability, CONFIG.FIERCE_METHOD)
end
function Remote.fireDash() return send(gameInfo and gameInfo.getDashAbility(), CONFIG.DASH_METHOD) end
function Remote.teardown()
  epoch += 1; keybindObject, gameInfo, utils = nil, nil, nil
  return true
end

-- contract
Remote.__contract = {
  requires = { GameInfo = "gameinfo", Utils = "utils" },
  requiresMethods = {
    Utils = { "getConfigValue" },
    GameInfo = {
      "isTrainingArea",
      "fireTrainingParry",
      "getDeflectAbility",
      "getDarkSealAbility",
      "getFierceDeflectAbility",
      "getDashAbility",
    },
  },
  provides = {
    "setup",
    "teardown",
    "fireParry",
    "fireDark",
    "fireFierce",
    "fireDash",
  },
}

return Remote
