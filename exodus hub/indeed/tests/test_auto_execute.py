"""Persistent startup scope and queued bootstrap cancellation."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class AutoExecuteTests(unittest.TestCase):
    def test_scope_persistence_disable_and_failed_queue_rollback(self):
        binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
        if not binary:
            self.skipTest('Luau required')
        code = r'''
local files, documents, queued = {}, {}, {}
local revision, observer, failQueue = 0, nil, false
local config = {AutoExecuteOnJoin = false, AutoExecuteAllGames = false, AutoExecute = true}
local http = {}
function http:JSONEncode(value)
  revision += 1
  local key = tostring(revision)
  documents[key] = {allGames = value.allGames, games = table.clone(value.games), entryURL = value.entryURL}
  return key
end
function http:JSONDecode(value) return documents[value] end
local game = {GameId = 123, PlaceId = 456, GetService = function() return http end}
local environment = {
  readfile = function(path) return assert(files[path]) end,
  writefile = function(path, source) files[path] = source end,
  isfile = function(path) return files[path] ~= nil end,
  isfolder = function() return true end, makefolder = function() end,
  delta = {AddTab = function() end},
  queue_on_teleport = function(source) if failQueue then error('queue unavailable') end; queued[#queued + 1] = source end,
}
local function getgenv() return environment end
local function warn() end
local errors = 0
local utils = {
  getConfigValue = function(key) return config[key] end,
  recordError = function() errors += 1 end,
  setConfig = function(patch)
    for key, value in pairs(patch) do config[key] = value end
    if observer then observer(patch) end
    return true
  end,
  observeConfig = function(callback) observer = callback; return {Disconnect = function() observer = nil end} end,
}
local AutoExecute = (function()
''' + (ROOT / 'core/auto_execute.luau').read_text() + r'''
end)()
local transport = {entryURL = function() return 'https://raw.githubusercontent.com/Repp35/Exodus-Hub/main/exodus%20hub/loader.luau' end}
AutoExecute.setup({Utils = utils}); AutoExecute.start(transport)
utils.setConfig({AutoExecuteOnJoin = true})
assert(files['DeltaPlugins/ExodusHub.luau'])
assert(#queued == 1)
local function saved() return documents[files['Exodus Hub/auto_execute.json']] end
assert(saved().games['u:123'] and not saved().allGames)
utils.setConfig({AutoExecuteAllGames = true}); assert(saved().allGames)
utils.setConfig({AutoExecuteOnJoin = false})
assert(not config.AutoExecuteAllGames, 'Disabling the parent must reset its child scope')
utils.setConfig({AutoExecuteOnJoin = true})
assert(not saved().allGames and saved().games['u:123'], 'Re-enabling must use the visible child state')
utils.setConfig({AutoExecuteAllGames = true})
utils.setConfig({AutoExecuteAllGames = false}); assert(not saved().allGames and saved().games['u:123'])
AutoExecute.teardown(); game.GameId = 999
AutoExecute.setup({Utils = utils}); AutoExecute.start(transport)
assert(not config.AutoExecuteOnJoin and saved().games['u:123'])
-- The queued bootstrap reads current preferences at execution time, not a captured on/off value.
utils.setConfig({AutoExecuteOnJoin = true})
utils.setConfig({AutoExecuteOnJoin = false})
game.GameId = 123; AutoExecute.teardown(); AutoExecute.setup({Utils = utils}); AutoExecute.start(transport)
utils.setConfig({AutoExecuteOnJoin = false})
assert(next(saved().games) == nil and not saved().allGames)
assert(config.AutoExecute == true, 'Startup toggle must not alter automatic updates')
-- No fetch is allowed after the setting is disabled, even for an already queued script.
local boot = assert(loadstring(queued[1]))
setfenv(boot, setmetatable({game = game, readfile = environment.readfile, getgenv = getgenv}, {__index = getfenv()}))
assert(pcall(boot))
AutoExecute.teardown(); AutoExecute.setup({Utils = utils}); AutoExecute.start(transport)
failQueue = true; utils.setConfig({AutoExecuteOnJoin = true})
assert(not config.AutoExecuteOnJoin and next(saved().games) == nil and errors == 1)
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'auto_execute.luau'
            path.write_text(code)
            result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

if __name__ == '__main__': unittest.main()
