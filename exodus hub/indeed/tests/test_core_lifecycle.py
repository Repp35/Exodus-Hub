"""Exercise the complete infrastructure modules with deterministic services."""
from pathlib import Path
import unittest
from test_raw_target_parry import run_lua
ROOT = Path(__file__).resolve().parents[2]

class CoreLifecycle(unittest.TestCase):
    def test_updater_factory_has_no_background_work_and_releases_failed_reload(self):
        source = (ROOT / 'modules/core/updater.luau').read_text()
        run_lua('''
local spawned=0; task={spawn=function(f) spawned=spawned+1; f() end,defer=function(f,...) f(...) end}
warn=function() end
local Updater=(function()
''' + source + '''
end)()
local failures=0
local instance=Updater.create({Exodus={Started=true},validRevision=function() return false end,
 resolveLatestRevision=function() error('offline') end})
assert(spawned==0)
assert(instance.reload(function() failures=failures+1 end))
assert(instance.reload(function() failures=failures+1 end))
assert(failures==2 and spawned==2)
''')

    def test_runtime_binds_once_and_dispatches_by_priority(self):
        source = (ROOT / 'modules/core/runtime.luau').read_text()
        run_lua('''
local Runtime=(function()
''' + source + '''
end)()
local callback; local watchers,maintenance=0,0; local calls={}
local gameinfo={applySync=function(x) return x end,getSyncData=function() end,
 installBallWatcher=function() watchers=watchers+1; return true end,
 bindBallSync=function(f) callback=f; return true end,
 startMaintenance=function() maintenance=maintenance+1; return true end,
 stopMaintenance=function() end,getDeflectAbility=function() return {} end}
local function subscriber(name) return {__contract={onBallSync=true},onBallSync=function() calls[#calls+1]=name end} end
local loaded={utils={isActive=function() return true end,trackGlobal=function() end},gameinfo=gameinfo,remote={},
 autoparry=subscriber('ap'),autospam=subscriber('spam')}
table.clone=function(x) local t={} for k,v in pairs(x) do t[k]=v end return t end
typeof=type
local result=Runtime.bind(loaded,{'autoparry','autospam'},{},function() error('unexpected error') end)
assert(result.ballSync and result.ballSyncSubscribers==2 and watchers==1 and maintenance==1)
callback({Sequence=1}); assert(calls[1]=='spam' and calls[2]=='ap')
''')

class SharedStatus(unittest.TestCase):
    def test_provider_failure_is_isolated_and_recovers_without_ui(self):
        source = (ROOT / 'modules/core/status.luau').read_text()
        run_lua('''
local Status=(function()
''' + source + '''
end)()
local reports=0; local fail=true; local calls=0
local providers={bad={getStatus=function() if fail then error('offline') end return {phase='ready'} end},
 good={getStatus=function() calls=calls+1; return {count=calls} end}}
assert(Status.configure(providers,function() reports=reports+1 end))
assert(Status.get('bad')==nil and Status.get('bad')==nil and reports==1)
local values=Status.collect(); assert(values.good.count==1 and values.bad==nil)
fail=false; assert(Status.get('bad').phase=='ready')
fail=true; assert(Status.get('bad')==nil and reports==2)
assert(Status.collect({'good'}).good.count==2)
''')

    def test_reentrant_provider_read_cannot_recurse_forever(self):
        source = (ROOT / 'modules/core/status.luau').read_text()
        run_lua('''
local Status=(function()
''' + source + '''
end)()
local reader;local count=0
reader=Status.create({self={getStatus=function()
 count=count+1;assert(reader.get('self')==nil);return {phase='ready'}
end}})
assert(reader.get('self').phase=='ready' and count==1)
''')
