-- [[ automatic updates ]]
--!optimize 2
-- @modules updates

local Updates = {}
local utils, hub
local transport
local generation = 0
local checking = false
local pending
local CONFIG = { POLL_SECONDS = 120, SAFE_SECONDS = 0.4, STATE_INTERVAL = 0.1 }

function Updates.teardown()
  generation += 1
  checking, pending, transport = false, nil, nil
  return true
end
function Updates.setup(deps)
  Updates.teardown()
  utils, hub = deps.Utils, deps.Hub
  return true
end
function Updates.awaitSafe(isCurrent)
  local safeSince
  while utils and utils.isActive() and (not isCurrent or isCurrent()) do
    if hub.canUpdate() then
      safeSince = safeSince or os.clock()
      if os.clock() - safeSince >= CONFIG.SAFE_SECONDS then
        return true
      end
    else
      safeSince = nil
    end
    task.wait(CONFIG.STATE_INTERVAL)
  end
  return false
end
function Updates.check()
  if checking or not transport or not utils.isActive() then
    return false
  end
  checking = true
  local owner, channel = generation, transport
  local function current() return owner == generation and utils.isActive() end
  local ok, reason = xpcall(function()
    local revision, err = channel.latest()
    if not current() then
      return
    end
    if not revision then
      error(err, 0)
    end
    if revision == _G.ExodusLastLoadedRevision then
      return
    end
    pending = revision
    local chunk, prepareError = channel.prepare(revision)
    if not chunk then
      error(prepareError, 0)
    end
    if not current() then
      return
    end
    -- The replacement downloads first, then rechecks the policy before stopping this session.
    _G.ExodusRequestedRevision = { revision = revision, automatic = true }
    chunk()
  end, function(err) return debug.traceback(tostring(err), 2) end)
  if owner == generation then
    checking = false
    if not ok then
      utils.recordError("Updates", reason)
    end
  end
  return ok
end
function Updates.start(channel)
  assert(type(channel.latest) == "function" and type(channel.prepare) == "function", "Missing update transport")
  transport = channel
  local owner = generation
  local function schedule()
    task.delay(CONFIG.POLL_SECONDS, function()
      if owner ~= generation or not utils.isActive() then
        return
      end
      if utils.getConfigValue("AutoExecute") == true then
        Updates.check()
      end
      if owner == generation and utils.isActive() then
        schedule()
      end
    end)
  end
  schedule()
  return true
end
function Updates.getStatus() return { checking = checking, revision = pending } end
Updates.__config = { schema = { AutoExecute = "boolean" }, defaults = { AutoExecute = true } }
Updates.__contract = {
  provides = { "setup", "teardown", "start", "check", "awaitSafe", "getStatus" },
  requires = { Utils = "utils", Hub = "hubapi" },
  requiresMethods = { Utils = { "isActive", "getConfigValue", "recordError" }, Hub = { "canUpdate" } },
}
return Updates
