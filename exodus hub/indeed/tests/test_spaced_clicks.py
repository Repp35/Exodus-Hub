"""Deadline dispatch spaces real attempts and never repays missed clicks in bursts."""
import unittest
from test_logic_reliability import COMMON, SPAM, module, run_case

class SpacedClicks(unittest.TestCase):
    def check(self, case):
        fixture='''
u.isDynamicSpamActive=function() return false end
local originalRead=u.getConfigValue
u.getConfigValue=function(k) if k=='ClickMethod' then return 'Deflect' end return originalRead(k) end
local heartbeat={Wait=function() coroutine.yield() end}
u.getRunService=function() return {Heartbeat=heartbeat} end
local dynamic={canSend=function() return false end}
r.fireNativeParry=function(guard) return r.fireParry(1,guard) end
local stamps={};local native=r.fireParry
r.fireParry=function(...) stamps[#stamps+1]=tm;return native(...) end
local waits={};task.wait=function(dt) waits[#waits+1]=dt;coroutine.yield() end
'''
        case=case.replace('AutoSpam=a}', 'AutoSpam=a,DynamicParry=dynamic}')
        run_case(COMMON+SPAM+fixture+module('spam.luau')+case)

    def test_requested_interval_and_late_wakeup_do_not_burst(self):
        self.check('''
mode='CPS';rate=20
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}));assert(count==1)
frame(.049);assert(count==1)
frame(.0011);assert(count==2)
frame(.5);assert(count==3,'late frame generated a catch-up burst')
frame(.001);assert(count==3,'deadline used scheduled instead of actual dispatch time')
for i=2,#stamps do assert(stamps[i]-stamps[i-1]>=.05-1e-9) end
''')

    def test_standard_native_minimum_spacing_applies_to_cps_ms_and_cpf(self):
        for mode, rate in (('CPS',1000),('MS',1),('CPF',20)):
            with self.subTest(mode=mode):
                self.check(f"mode='{mode}';rate={rate};assert(mod.setup({{Utils=u,Remote=r,GameInfo=g,AutoSpam=a}}));for i=1,100 do frame(.001) end;for i=2,#stamps do assert(stamps[i]-stamps[i-1]>=.008-1e-9) end;assert(count>1)")

    def test_cancellation_stops_queued_click(self):
        self.check("mode='CPS';rate=20;assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}));assert(count==1);manual=false;frame(.1);assert(count==1)")
