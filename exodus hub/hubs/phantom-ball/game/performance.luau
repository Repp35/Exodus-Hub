-- [[ Phantom Ball performance extension ]]
--!optimize 2
local Performance = {}
local root, activation
function Performance.teardown()
  if root then
    root.destroy()
  end
  root, activation = nil, nil
  return true
end
function Performance.setup(deps)
  Performance.teardown()
  local options, utils = deps.Options, deps.Utils
  root = deps.Lifetime.scope()
  local cleanup = { Disconnect = root.destroy }
  utils.trackGlobal(cleanup)
  root.add(function() utils.untrackGlobal(cleanup) end)
  local values = {}
  local function refreshOptions()
    values = {
      GameGenerators = true,
      GameNoVFX = options.isEnabled("AntiLagRemoveEffects"),
      GameReducedUI = options.isEnabled("AntiLagRemoveEffects"),
      GameSwordSounds = not options.isEnabled("PhantomRemoveSwordSounds"),
      GameCosmeticAudio = options.isEnabled("PhantomMuteCosmetics"),
      GameKeepCombatAudio = true,
      GameMuteMusic = options.isEnabled("PhantomMuteMusic"),
      GameReducedHeadLook = options.isEnabled("PhantomReduceHeadLook"),
      RestoreLatest = false,
    }
  end
  local function getOption(key) return values[key] end
  local adapter
  local function sync()
    refreshOptions()
    if not options.isEnabled("AntiLagEnabled") then
      if activation then
        activation.destroy()
      end
      activation, adapter = nil, nil
      return
    end
    if not activation then
      activation = root.child()
      local player = utils.getLocalPlayer()
      adapter = deps.Native.create({
        Workspace = workspace,
        Player = player,
        PlayerScripts = player:FindFirstChild("PlayerScripts"),
        ReplicatedStorage = game:GetService("ReplicatedStorage"),
        SoundService = game:GetService("SoundService"),
        Scope = activation,
        Binding = deps.Binding,
        ConnectPhysics = function(callback)
          local scope = activation.child()
          deps.Controller.connectPhysics(scope, callback)
          return { Disconnect = scope.destroy }
        end,
      }, getOption)
      activation.add(function() adapter:Destroy() end)
      adapter:SetEnabled(true)
    else
      adapter:Refresh()
    end
  end
  root.add(
    options.observe(
      { "AntiLagEnabled", "AntiLagRemoveEffects", "PhantomRemoveSwordSounds", "PhantomMuteMusic", "PhantomMuteCosmetics", "PhantomReduceHeadLook" },
      sync
    )
  )
  sync()
  return true
end
Performance.__config = {
  schema = { PhantomMuteMusic = "boolean", PhantomMuteCosmetics = "boolean", PhantomReduceHeadLook = "boolean" },
  defaults = { PhantomMuteMusic = true, PhantomMuteCosmetics = true, PhantomReduceHeadLook = true },
}
Performance.__contract = {
  provides = { "setup", "teardown" },
  requires = {
    Options = "options",
    Utils = "utils",
    Lifetime = "lifetime",
    Native = "nativevisuals",
    Binding = "propertybinding",
    Controller = "universalcontroller",
  },
  requiresMethods = {
    Options = { "get", "isEnabled", "observe" },
    Utils = { "getLocalPlayer", "trackGlobal", "untrackGlobal" },
    Lifetime = { "scope" },
    Native = { "create" },
    Binding = { "apply", "release" },
    Controller = { "connectPhysics" },
  },
}
return Performance
