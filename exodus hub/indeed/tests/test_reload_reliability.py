"""Behavioral checks for reload failure handling using the existing Lua shim."""
from pathlib import Path
import unittest
from test_raw_target_parry import run_lua

SOURCE = (Path(__file__).resolve().parents[2] / 'loader.luau').read_text()
RELOAD = SOURCE[SOURCE.index('local reloadInFlight = false'):SOURCE.index('local startupPerformed = false')]

class ReloadReliability(unittest.TestCase):
    def test_unexpected_failure_releases_lock_and_allows_retry(self):
        run_lua('''
local task={spawn=function(f) f() end, defer=function(f,...) f(...) end}
local warned=0; local failures=0; local attempts=0
local function warn() warned=warned+1 end
local function clearPersistent() end
local function notifyPersistent() end
local function validRevision(x) return type(x)=='string' and #x==40 end
local function resolveLatestRevision() attempts=attempts+1; error('network exception') end
local Exodus={Started=true}; local BASE_URL=''; local PROJECT_PATH=''
''' + RELOAD + '''
local function failed() failures=failures+1 end
assert(reloadLatest(failed)); assert(reloadLatest(failed))
assert(attempts==2 and failures==2 and warned==2)
''')

    def test_stale_session_cannot_start_replacement(self):
        run_lua('''
local queued; local executed=false
local task={spawn=function(f) queued=f end, defer=function(f,...) f(...) end}
local function warn() end
local function clearPersistent() end
local function notifyPersistent() end
local function validRevision(x) return type(x)=='string' and #x==40 end
local function requestDelivery() _G.ExodusLoaderSessionToken='new'; return 'source' end
local function compile() return function() executed=true end end
local function waitForClashToEnd() return true end
local Exodus={Started=true}; local BASE_URL=''; local PROJECT_PATH=''
_G.ExodusLoaderSessionToken='old'
''' + RELOAD + '''
assert(reloadLatest(nil,string.rep('a',40),false)); queued()
assert(not executed and not reloadInFlight)
''')

if __name__ == '__main__':
    unittest.main()
