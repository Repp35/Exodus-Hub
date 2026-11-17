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
local function resolveLatestRevision() return string.rep('a',40),nil,nil,{['exodus hub/loader.luau']='sig'} end
local function signatureValid(s) return s=='sig' end
local function fingerprint() return 'sig' end
local sourceCache={}
local function cachedSource() return nil end
local function requestDelivery() _G.ExodusLoaderSessionToken='new'; return 'source' end
local function compile() return function() executed=true end end
local function waitForClashToEnd() return true end
local Exodus={Started=true}; local BASE_URL=''; local PROJECT_PATH=''
_G.ExodusLoaderSessionToken='old'
''' + RELOAD + '''
assert(reloadLatest(nil,string.rep('a',40),false)); queued()
assert(not executed and not reloadInFlight)
''')

class SourceCache(unittest.TestCase):
    def test_cache_checks_content_and_all_runtime_signatures(self):
        helpers = SOURCE[SOURCE.index('local function signatureValid'):SOURCE.index('-- registry')]
        run_lua('''
local MODULE_MANIFEST={{path='one'},{path='two'}}
local function fingerprint(source) return source end
_G.ExodusSourceCache={['exodus hub/one']='12345678'}
''' + helpers + '''
assert(cachedSource('exodus hub/one','12345678')=='12345678')
assert(cachedSource('exodus hub/one','87654321')==nil)
assert(sourceCache['exodus hub/one']==nil)
local a={['exodus hub/loader.luau']='11111111',['exodus hub/one']='22222222',['exodus hub/two']='33333333'}
local b={['exodus hub/loader.luau']='11111111',['exodus hub/one']='22222222',['exodus hub/two']='33333333'}
assert(sameRuntimeSignatures(a,b)); b['exodus hub/two']='44444444'
assert(not sameRuntimeSignatures(a,b)); b['exodus hub/two']=nil
assert(not sameRuntimeSignatures(a,b))
''')

    def test_only_changed_or_corrupt_source_is_downloaded(self):
        module = SOURCE[SOURCE.index('local function loadModule('):SOURCE.index('local function authorizationURL')]
        run_lua('''
local cache={}; local expected='version1'; local downloads=0
local function signatureFor() return expected end
local function signatureValid(s) return type(s)=='string' end
local function fingerprint(s) return s end
local function cachedSource(key,sig) local s=cache[key]; if s==sig then return s end; cache[key]=nil end
local sourceCache=cache
local function requestDelivery() downloads=downloads+1; return expected end
local function compile(_,source) return function() return source end end
local function deliveryFallbackURL() end
local function buildCDNURL() end
''' + module + '''
assert(loadModule('m','m','url')); assert(downloads==1)
assert(loadModule('m','m','url')); assert(downloads==1)
expected='version2'; assert(loadModule('m','m','url')); assert(downloads==2)
cache['exodus hub/m']='corrupt'; assert(loadModule('m','m','url')); assert(downloads==3)
''')

if __name__ == '__main__':
    unittest.main()
