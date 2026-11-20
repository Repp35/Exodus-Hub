"""Behavioral checks for cancellation at the final parry dispatch boundary."""
import re
import unittest

from test_raw_target_parry import ROOT, run_lua

PRELUDE = """
local permit=true; local sends=0; local delayed={}; local method='Direct'
local tm=10;os.clock=function() return tm end
local lookupCalls,floatWrites,bufferCreates=0,0,0;local sentPackets={}
local function instance(kind)
  return {instance=true,Parent=true,IsA=function(_,name) return name==kind end}
end
function typeof(value) return type(value)=='table' and value.instance and 'Instance' or type(value) end
local remote=instance('RemoteEvent'); local unreliable=instance('UnreliableRemoteEvent')
unreliable.Parent=remote
remote.FireServer=function(_,packet) sends=sends+1;sentPackets[#sentPackets+1]=packet end
unreliable.FireServer=remote.FireServer
function getrenv() lookupCalls=lookupCalls+1;return {_G={did2=remote,did2u=unreliable}} end
local xyz={X=0,Y=0,Z=0}
workspace={CurrentCamera={CFrame={Position=xyz,LookVector=xyz}},GetServerTimeNow=function() return 10 end}
buffer={create=function() bufferCreates=bufferCreates+1;return {} end,copy=function(dst,at,src,from,n) for k,value in pairs(src) do if k>=from and k<from+n then dst[at+k-from]=value end end end}
for _,name in ipairs({'writeu8','writeu16','writef64'}) do buffer[name]=function(packet,offset,value) packet[offset]=value end end
buffer.writef32=function(packet,offset,value) floatWrites=floatWrites+1;packet[offset]=value end
local function later(fn,...) local args=table.pack(...);delayed[#delayed+1]=function() fn(table.unpack(args,1,args.n)) end end
task={delay=function(_,fn,...) later(fn,...) end,defer=function(fn,...) later(fn,...) end}
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

    def test_prepared_direct_keeps_count_sequence_and_retransmissions(self):
        self.check("""
local dispatch=module.prepareParry(guard)
for i=1,100 do assert(dispatch()) end
assert(sends==200 and #delayed==100,'immediate transport count changed')
assert(lookupCalls==1 and floatWrites==6,'repeated remote/camera preparation')
assert(bufferCreates==101,'packet prefix was rebuilt per click')
for i=2,100 do local prev=sentPackets[(i-2)*2+1];local curr=sentPackets[(i-1)*2+1];assert(prev~=curr and (curr[25]-prev[25])%65536==1,'packet overwritten or sequence reused') end
for _,fn in ipairs(delayed) do fn() end
assert(sends==300,'retransmissions were reduced')
""")

    def test_prepared_direct_refreshes_camera_and_invalid_remote(self):
        self.check("""
local dispatch=module.prepareParry(guard);assert(dispatch())
local first=sentPackets[1]
workspace.CurrentCamera.CFrame={Position={X=9,Y=8,Z=7},LookVector={X=1,Y=0,Z=0}}
assert(dispatch());assert(sentPackets[3][1]==9 and first[1]==0,'camera prefix stale or old packet mutated')
local replacement=instance('RemoteEvent');replacement.FireServer=remote.FireServer
remote.Parent=nil;remote=replacement;unreliable.Parent=remote
assert(dispatch());assert(lookupCalls==2,'destroyed remote not refreshed immediately')
""")

    def test_prepared_dispatch_observes_cancellation_and_teardown(self):
        self.check("""
local dispatch=module.prepareParry(guard);assert(dispatch());permit=false
assert(not dispatch() and sends==2);permit=true
module.teardown();assert(not dispatch() and sends==2,'prepared sender outlived runtime')
for _,fn in ipairs(delayed) do fn() end;assert(sends==2)
""")

    def test_prepared_direct_cache_expires_without_delaying_send(self):
        self.check("""
local dispatch=module.prepareParry(guard);assert(dispatch());tm=tm+.01;assert(dispatch())
assert(lookupCalls==2 and sends==4,'cache expiry delayed or dropped sends')
""")

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

    def test_standard_calls_native_once_without_inspecting_click_state(self):
        self.check("""
method='Deflect'
local calls=0
local ability=setmetatable({Deflect=function(self) calls=calls+1 end},{__index=function(_,key) error('unexpected native state read: '..key) end})
info.getDeflectAbility=function() return ability end
assert(module.fireParry(1,guard));assert(calls==1 and sends==0 and #delayed==0)
""")

    def test_valid_nil_return_with_new_click_is_accepted(self):
        self.check("""
method='Deflect'
local ability={ClickInstances={},LastDeflectCallAt=1}
ability.Deflect=function(self) self.LastDeflectCallAt=2;self.ClickInstances[1]={};sends=sends+1 end
info.getDeflectAbility=function() return ability end
assert(module.fireParry(1,guard));assert(sends==1)
""")


if __name__ == '__main__':
    unittest.main()
