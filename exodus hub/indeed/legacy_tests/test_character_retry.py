"""Transient module bind failure must not permanently disable combat."""
import re
import unittest
from test_raw_target_parry import ROOT, run_lua

class CharacterRetry(unittest.TestCase):
    def test_retry_after_transient_failure(self):
        source=(ROOT/'core/character.luau').read_text()
        source=re.sub(r'([A-Za-z_][\w.]*) \+= ([^;\n]+?)(?=;|\n| end)',lambda m:f'{m[1]} = {m[1]} + ({m[2]})',source)
        run_lua('''
local function signal() return {Connect=function() return {Disconnect=function() end} end} end
local root={Parent=true,IsA=function() return true end}
local char={Parent=true,AncestryChanged=signal(),ChildAdded=signal(),FindFirstChild=function() return root end,FindFirstChildOfClass=function() end}
local player={Character=char,CharacterAdded=signal(),CharacterRemoving=signal()}
local pending; task={spawn=function(fn) fn() end,delay=function(_,fn) pending=fn end}
local utils={getLocalPlayer=function() return player end,isActive=function() return true end,apiVersion=function() return 1 end}
for _,k in ipairs({'trackGlobal','untrackGlobal','trackCharacter','disconnectCharacterConnections','setManualSpamActive','setAutoSpamActive','recordTransition','recordError'}) do utils[k]=function() end end
local attempts=0; local bound={{name='test',bind=function() attempts=attempts+1; return attempts>1 end,detach=function() end}}
local mod=(function()\n''' + source + '''\nend)()
assert(mod.setup({Utils=utils,Spam={resetState=function() end},characterBinds=bound}))
assert(attempts==1 and mod.getStatus().phase=='waiting' and pending)
pending(); assert(attempts==2 and mod.getStatus().phase=='bound')
mod.teardown()
''')

if __name__ == '__main__': unittest.main()
