"""Behavioral checks for cancellation at the final parry dispatch boundary."""
import re
import unittest

from test_raw_target_parry import ROOT, run_lua

PRELUDE = """
local permit=true; local sends=0; local delayed={}; local method='Direct'
local function instance(kind)
  return {instance=true,Parent=true,IsA=function(_,name) return name==kind end}
end
function typeof(value) return type(value)=='table' and value.instance and 'Instance' or type(value) end
local remote=instance('RemoteEvent'); local unreliable=instance('UnreliableRemoteEvent')
unreliable.Parent=remote
remote.FireServer=function() sends=sends+1 end
unreliable.FireServer=remote.FireServer
function getrenv() return {_G={did2=remote,did2u=unreliable}} end
local xyz={X=0,Y=0,Z=0}
workspace={CurrentCamera={CFrame={Position=xyz,LookVector=xyz}},GetServerTimeNow=function() return 10 end}
buffer={create=function() return {} end}
for _,name in ipairs({'writeu8','writeu16','writef32','writef64'}) do buffer[name]=function() end end
task={delay=function(_,fn) delayed[#delayed+1]=fn end,defer=function(fn) delayed[#delayed+1]=fn end}
local storage={FindFirstChild=function() end}
local vim={SendKeyEvent=function(_,down) if down then sends=sends+1 end end}
game={GetService=function(_,name) if name=='ReplicatedStorage' then return storage elseif name=='VirtualInputManager' then return vim else return {} end end}
local info={isTrainingArea=function() return false end}
local utils={getConfigValue=function() return method end}
local function guard() return permit end
"""


class ParryDispatch(unittest.TestCase):
    def check(self, case):
        source = (ROOT / 'aux/remote.luau').read_text()
        source = re.sub(r'([A-Za-z_][\w.]*) \+= ([^;\n]+?)(?=;|\n| end)', lambda m: f'{m[1]} = {m[1]} + ({m[2]})', source)
        run_lua(PRELUDE + 'local module=(function()\n' + source + '\nend)()\n' +
                'assert(module.setup({GameInfo=info,Utils=utils}))\n' + case)

    def test_direct_delayed_resend_is_cancelled(self):
        self.check("""
assert(module.fireParry(1,guard)); assert(sends==2 and #delayed==1)
permit=false; delayed[1](); assert(sends==2,'cancelled request resent after 30ms')
""")

    def test_direct_delayed_resend_remains_when_allowed(self):
        self.check("""
assert(module.fireParry(1,guard)); delayed[1]()
assert(sends==3,'valid retransmission was removed')
""")

    def test_direct_rechecks_after_remote_lookup(self):
        self.check("""
local lookup=getrenv
getrenv=function() permit=false; return lookup() end
assert(not module.fireParry(1,guard)); assert(sends==0)
""")

    def test_ability_rechecks_after_lookup(self):
        self.check("""
method='Default'
info.getDeflectAbility=function() permit=false; return {Deflect=function() sends=sends+1 end} end
assert(not module.fireParry(1,guard)); assert(sends==0)
""")

    def test_input_rechecks_after_keybind_lookup(self):
        self.check("""
method='Input'
local key={instance=true,EnumType={}}
Enum={KeyCode=key.EnumType}; Enum.KeyCode.Unknown={}
local ty=typeof; typeof=function(value) if value==key then return 'EnumItem' end return ty(value) end
info.getDeflectAbility=function() return {GetKeybindBySlotID=function() permit=false; return {Key=key} end} end
assert(not module.fireParry(1,guard)); assert(sends==0)
""")


if __name__ == '__main__':
    unittest.main()
