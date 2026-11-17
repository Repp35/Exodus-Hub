"""A manual reload supersedes a queued automatic update without waiting."""
from pathlib import Path
import unittest
from test_raw_target_parry import run_lua

class UpdateQueue(unittest.TestCase):
    def test_manual_supersedes_waiting_automatic_job(self):
        source=(Path(__file__).resolve().parents[2]/'modules/core/updater.luau').read_text()
        run_lua('''
local Updater=(function()
'''+source+'''
end)()
local jobs={};task={spawn=function(f)
 local co=coroutine.create(f);jobs[#jobs+1]=co;local ok,err=coroutine.resume(co);assert(ok,err)
end,defer=function(f,...) f(...) end}
warn=function() error('unexpected failure') end
_G.ExodusLoaderSessionToken='session'
local executed,matchWaits,clashWaits=0,0,0
local revision=string.rep('b',40)
local hub={Started=true,Revision=string.rep('a',40)}
local service=Updater.create({Exodus=hub,validRevision=function(v) return type(v)=='string' and #v==40 end,
 clearPersistent=function() end,notifyPersistent=function() end,
 resolveLatestRevision=function() return revision,nil,nil,{} end,
 prepareLoader=function() return function() executed=executed+1 end end,
 waitForMatchToEnd=function(waiting,current)
  matchWaits=matchWaits+1;waiting();coroutine.yield()
  return current(),true
 end,
 waitForClashToEnd=function() clashWaits=clashWaits+1;return true end})
assert(service.reload(nil,revision,true));assert(executed==0 and matchWaits==1)
assert(service.reload(nil,nil,false));assert(executed==1 and clashWaits==0 and matchWaits==1)
local ok,err=coroutine.resume(jobs[1]);assert(ok,err)
assert(executed==1,'cancelled automatic job executed after manual reload')
''')
