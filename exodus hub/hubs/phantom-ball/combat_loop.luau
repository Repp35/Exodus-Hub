-- [[ combat loop ]]

-- code
local CombatLoop = {}
local utils
local gameInfo
local profiler
local autoSpam
local autoParry
local autoDash
local fierce
local cooldown
local scope
local running = false
local errorAt = {}
local function invoke(name, callback, ...)
  if not utils or not profiler then return end
  local metrics, reporting = profiler, utils; local started = metrics.begin(name)
  local ok, message = pcall(callback, ...); metrics.finish(name, started)
  if not ok then
    local now = os.clock()
    if not errorAt[name] or now - errorAt[name] >= 1 then errorAt[name] = now; reporting.recordError(name, message) end
  end
end
local function dispatch(data, dt)
  if not utils or not utils.isActive() then return end
  local info, spam, parry, rescue, cd, dash = gameInfo, autoSpam, autoParry, fierce, cooldown, autoDash; info.beginEvaluation()
  invoke("combat.cooldown", cd.step); local automatic = utils.getConfigValue("AutoSpam") == true or spam.isActive()
  if data then
    if automatic then invoke("combat.autospam", spam.onBallSync, data) end
    invoke("combat.autoparry", parry.onBallSync, data); invoke("combat.autodash", dash.onBallSync, data)
  else
    if automatic then invoke("combat.autospam", spam.step, dt) end
    invoke("combat.autoparry", parry.step, dt)
  end
  invoke("combat.fierce", rescue.onBallSync); info.endEvaluation()
end
function CombatLoop.pulse(dt)
  if running then return end
  running = true; dispatch(nil, dt)
  running = false
end
function CombatLoop.onBallSync(data)
  local previous = running; running = true
  dispatch(data); running = previous
end
function CombatLoop.teardown()
  if scope then scope.destroy(); scope = nil end
  running = false; table.clear(errorAt)
  utils, gameInfo, profiler, autoSpam, autoParry, fierce, cooldown, autoDash = nil, nil, nil, nil, nil, nil, nil, nil
end
function CombatLoop.setup(deps)
  CombatLoop.teardown(); utils, gameInfo, profiler = deps.Utils, deps.GameInfo, deps.Profiler
  autoSpam, autoParry, fierce, cooldown, autoDash = deps.AutoSpam, deps.AutoParry, deps.AutoFierce, deps.Cooldown, deps.AutoDash; scope = deps.Lifetime.scope()
  local service = utils.getRunService(); scope.connect(service.PostSimulation or service.Heartbeat, CombatLoop.pulse)
  if service.PreSimulation then
    scope.connect(service.PreSimulation, function(dt)
      if autoParry.isDeadlineDue() then CombatLoop.pulse() end
    end)
  end
  scope.add(gameInfo.observeTraining(CombatLoop.pulse)); scope.add(cooldown.observeDeflect(CombatLoop.pulse))
  scope.add(utils.observeConfig(function() CombatLoop.pulse() end))
  return true
end
CombatLoop.__contract = {
  requires = {
    Utils = "utils",
    GameInfo = "gameinfo",
    Profiler = "profiler",
    Lifetime = "lifetime",
    AutoSpam = "autospam",
    AutoParry = "autoparry",
    AutoDash = "autodash",
    AutoFierce = "autofierce",
    Cooldown = "cooldown",
  },
  requiresMethods = {
    Utils = { "isActive", "getRunService", "recordError", "observeConfig", "getConfigValue" },
    GameInfo = { "beginEvaluation", "endEvaluation", "observeTraining" },
    Profiler = { "begin", "finish" },
    Lifetime = { "scope" },
    AutoSpam = { "step", "onBallSync", "isActive" },
    AutoParry = { "step", "isDeadlineDue", "onBallSync" },
    AutoDash = { "onBallSync" },
    AutoFierce = { "onBallSync" },
    Cooldown = { "step", "observeDeflect" },
  },
  provides = { "setup", "teardown", "pulse", "onBallSync" },
  onBallSync = true,
}

return CombatLoop
