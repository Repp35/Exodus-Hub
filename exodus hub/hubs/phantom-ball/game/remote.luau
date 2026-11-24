-- [[ remote ]]

-- module
local Remote = {}
local gameInfo
local utils
local epoch = 0
local keybindObject
local inputService
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
  if typeof(remote) == "Instance" and remote:IsA("RemoteEvent") and remote.Parent ~= nil then
    local unreliable = rawget(globals, "did2u")
    if typeof(unreliable) ~= "Instance" or not unreliable:IsA("UnreliableRemoteEvent") or unreliable.Parent ~= remote then unreliable = remote:FindFirstChild("u") end
    return remote, unreliable
  end
  local remotes = ReplicatedStorage:FindFirstChild("Remotes"); local player = Players.LocalPlayer
  remote = remotes and player and (remotes:FindFirstChild("pu_" .. player.UserId) or remotes:FindFirstChild(""))
  if remote and remote:IsA("RemoteEvent") then return remote, remote:FindFirstChild("u") end
end
local function resendDirect(owner, remote, unreliable, guard, packet)
  if epoch == owner and gameInfo and unreliable.Parent == remote and remote.Parent ~= nil and allowed(guard) then pcall(unreliable.FireServer, unreliable, packet) end
end
local function fireDirect(guard, context)
  local time = os.clock()
  local remote, unreliable
  if context.remote and context.remote.Parent ~= nil and time >= context.checkedAt and time - context.checkedAt < 1 / 240 then
    remote, unreliable = context.remote, context.unreliable
    if unreliable and unreliable.Parent ~= remote then unreliable = nil end
  else
    remote, unreliable = directRemote(); context.remote, context.unreliable, context.checkedAt = remote, unreliable, time
  end
  if not remote then return false, "Remote de Deflect indisponível" end
  local camera = workspace.CurrentCamera
  if not camera then return false, "Câmera indisponível" end
  local cf = camera.CFrame
  if not context.prefix or context.camera ~= camera or context.frame ~= cf then
    local prefix = buffer.create(25); buffer.writeu8(prefix, 0, 1)
    local pos, look = cf.Position, cf.LookVector
    buffer.writef32(prefix, 1, pos.X); buffer.writef32(prefix, 5, pos.Y)
    buffer.writef32(prefix, 9, pos.Z); buffer.writef32(prefix, 13, look.X)
    buffer.writef32(prefix, 17, look.Y); buffer.writef32(prefix, 21, look.Z)
    context.prefix, context.camera, context.frame = prefix, camera, cf
  end
  local packet = buffer.create(35); buffer.copy(packet, 0, context.prefix, 0, 25)
  directSequence = (directSequence + 1) % 65536; buffer.writeu16(packet, 25, directSequence)
  buffer.writef64(packet, 27, workspace:GetServerTimeNow())
  if not allowed(guard) then return false, "Deflect cancelado" end
  remote:FireServer(packet)
  if unreliable and unreliable:IsA("UnreliableRemoteEvent") then pcall(unreliable.FireServer, unreliable, packet); task.delay(0.03, resendDirect, epoch, remote, unreliable, guard, packet) end
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
local function releaseInput(vim, input) vim:SendKeyEvent(false, input, false, game) end
local function fireInput(guard)
  local input = configuredInput(); inputService = inputService or game:GetService("VirtualInputManager")
  local vim = inputService
  if not allowed(guard) then return false, "Deflect cancelado" end
  vim:SendKeyEvent(true, input, false, game); task.defer(releaseInput, vim, input)
  return true
end

-- public-api
local function dispatchParry(info, guard, context, native, checked)
  if checked then
    local input = game:GetService("UserInputService")
    if input and type(input.GetFocusedTextBox) == "function" and input:GetFocusedTextBox() then return false, "entrada de texto ativa" end
  end
  local method = native and "Deflect" or utils.getConfigValue("ClickMethod")
  if method == "Input" then return fireInput(guard) end
  if info.isTrainingArea() then
    if not allowed(guard) then return false, "Deflect cancelado" end
    local sent, detail = info.fireTrainingParry(); return sent, detail
  end
  if method == "Direct" then return fireDirect(guard, context) end
  local ability = info.getDeflectAbility()
  if not allowed(guard) then return false, "Deflect cancelado" end
  if not ability then return false, "Deflect não equipado ou indisponível" end
  if checked then
    local nativeBefore = ability.LastDeflectCallAt; local before = info.getDeflectCallStamp(ability)
    local result = ability:Deflect()
    if result == false then return false, "Deflect recusado pelo cliente" end
    local after = info.getDeflectCallStamp(ability)
    if type(nativeBefore) == "number" or type(ability.LastDeflectCallAt) == "number" then
      if ability.LastDeflectCallAt == nativeBefore then return false, "Deflect recusado pelo cliente" end
      return true
    end
    if type(before) == "number" or type(after) == "number" then
      if after == before then return false, "Deflect recusado pelo cliente" end
    end
    return true
  end
  ability:Deflect(); return true
end
function Remote.prepareParry(callerGuard)
  local owner, info, context = epoch, gameInfo, {}
  local function guard() return owner == epoch and gameInfo == info and allowed(callerGuard) end
  return function()
    if not info or owner ~= epoch or gameInfo ~= info then return false, "Remote não inicializado" end
    return dispatchParry(info, guard, context)
  end
end
function Remote.fireNativeParry(guard) return dispatchParry(gameInfo, guard, {}, true) end
function Remote.fireParry(_flag, callerGuard) return Remote.prepareParry(callerGuard)() end
function Remote.fireCheckedParry(guard) return dispatchParry(gameInfo, guard, {}, false, true) end
function Remote.fireDark(eventId, cameraFrame) return send(gameInfo and gameInfo.getDarkSealAbility(), CONFIG.DARK_METHOD, eventId, cameraFrame) end
function Remote.fireFierce(guard)
  local owner = epoch; local ability = gameInfo and gameInfo.getFierceDeflectAbility()
  if owner ~= epoch or not gameInfo or not allowed(guard) then return false, "Fierce cancelado" end
  return send(ability, CONFIG.FIERCE_METHOD)
end
function Remote.fireDash() return send(gameInfo and gameInfo.getDashAbility(), CONFIG.DASH_METHOD) end
function Remote.teardown()
  epoch += 1; keybindObject, inputService, gameInfo, utils = nil, nil, nil, nil
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
      "getDeflectCallStamp",
      "getDarkSealAbility",
      "getFierceDeflectAbility",
      "getDashAbility",
    },
  },
  provides = {
    "setup",
    "teardown",
    "fireParry",
    "fireCheckedParry",
    "prepareParry",
    "fireNativeParry",
    "fireDark",
    "fireFierce",
    "fireDash",
  },
}

return Remote
