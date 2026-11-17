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


class RequestTimeout(unittest.TestCase):
    def test_hung_requests_time_out_and_pending_count_recovers(self):
        source = SOURCE[SOURCE.index('local requestState ='):SOURCE.index('local function request(url, headers)')]
        source = source.replace('requestState.pending += 1', 'requestState.pending = requestState.pending + 1')
        source = source.replace('requestState.pending -= 1', 'requestState.pending = requestState.pending - 1')
        run_lua('''
local CONFIG={MAX_PENDING_REQUESTS=1,REQUEST_TIMEOUT=2}
local now=0; os.clock=function() return now end
local delayed; local task={spawn=function(f) delayed=f end,wait=function() now=now+1 end}
local requestFunction=function() return {StatusCode=200,Body='ok'} end
local function headerValue() end
local function retryAfter() return 0 end
_G.ExodusRequestState=nil
''' + source + '''
local body,err=requestOnce('url',{})
assert(body==nil and err:find('limite') and requestState.pending==1)
body,err=requestOnce('url',{})
assert(body==nil and err:find('pendentes') and requestState.pending==1)
delayed(); assert(requestState.pending==0)
task.spawn=function(f) f() end
assert(requestOnce('url',{})=='ok' and requestState.pending==0)
''')

class ParallelPreparation(unittest.TestCase):
    def test_downloads_overlap_authorization_and_execution_waits(self):
        start = SOURCE.index('  local urls = buildURLs(version); local authorizationDone')
        end = SOURCE.index('  printStartup("Exodus: Initializing...")', start)
        preparation = SOURCE[start:end]
        run_lua('''
local version='revision'; local authorizationTask; local started=false; local downloaded=false
local task={spawn=function(f) authorizationTask=f end,wait=function() assert(downloaded); authorizationTask() end}
local CONFIG={DOWNLOAD_TIMEOUT=60}
local function buildURLs() return {} end
local function authorizeRevision() assert(downloaded); return true end
local function loadModules() assert(authorizationTask); downloaded=true; return {} end
local function startup()
''' + preparation + '''
 started=true; return true
end
assert(startup() and started and downloaded)
''')

if __name__ == '__main__':
    unittest.main()
