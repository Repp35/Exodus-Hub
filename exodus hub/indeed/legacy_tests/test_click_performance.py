"""Click rate, cancellation and metrics for the allocation-light scheduler."""
import unittest
from test_logic_reliability import COMMON, SPAM, module, run_case

class ClickPerformance(unittest.TestCase):
    def check(self,case):
        fixture = '''
u.isDynamicSpamActive=function() return false end
local heartbeat={Wait=function() coroutine.yield() end}
u.getRunService=function() return {Heartbeat=heartbeat} end
local dynamic={canSend=function() return false end}
'''
        case=case.replace('AutoSpam=a}', 'AutoSpam=a,DynamicParry=dynamic}')
        run_case(COMMON+SPAM+fixture+module('combat/spam.luau')+case)

    def test_lag_and_high_rates_are_not_capped(self):
        self.check('''
mode='CPS';rate=2000
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
frame(.25);assert(count==500,'elapsed time or burst was capped')
frame(.25);assert(count==1000,'rate changed after lag')
''')

    def test_fractional_cpf_accumulates(self):
        self.check('''
mode='CPF';rate=1.5
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
for i=1,10 do frame(.016) end
assert(count==15,'fractional CPF was rounded down')
''')

    def test_initial_auto_click_is_counted_in_rate(self):
        self.check('''
mode='CPS';rate=20;manual=false
u.isAutoSpamActive=function() return true end;a.canSend=function() return true end
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}));assert(count==1)
for i=1,100 do frame(.01) end
assert(count==20,'initial click was extra or lost')
''')

    def test_exact_counts_at_multiple_modes_and_frame_rates(self):
        for mode,rate in (('CPS',600),('MS',2),('CPF',64)):
            for fps in (30,60,144,240):
                with self.subTest(mode=mode,fps=fps):
                    expected=rate*fps if mode=='CPF' else 1000/rate if mode=='MS' else rate
                    self.check(f"mode='{mode}';rate={rate};assert(mod.setup({{Utils=u,Remote=r,GameInfo=g,AutoSpam=a}}));for i=1,{fps} do frame(1/{fps}) end;assert(math.abs(count-{expected})<=1,'rate changed');assert(mod.getStatus().attemptsLastSecond==count)")

    def test_prepared_sender_is_built_once_and_checks_every_click(self):
        self.check('''
mode='CPF';rate=100;local builds,checks=0,0
r.prepareParry=function(guard)
 builds=builds+1
 return function() if not guard() then return false end;checks=checks+1;count=count+1;return true end
end
r.fireParry=function() error('slow dispatch used') end
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
for i=1,60 do frame(1/60) end
assert(builds==1 and checks==6000 and count==6000)
local s=mod.getStatus();assert(s.attemptsLastSecond==6000 and s.acceptedLastSecond==6000)
manual=false;frame(1.1);assert(mod.getStatus().acceptedLastSecond==0)
''')

    def test_same_burst_stops_when_guard_changes(self):
        self.check('''
mode='CPF';rate=100
r.prepareParry=function(guard) return function() assert(guard());count=count+1;manual=false;return true end end
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}));frame(.016)
assert(count==1,'cancelled burst continued')
''')


    def test_grouped_metrics_preserve_partial_acceptances(self):
        self.check("""
mode='CPF';rate=10;u.recordError=function() end
r.prepareParry=function(guard) return function() assert(guard());count=count+1;return count%2==0,'refused' end end
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
for i=1,60 do frame(1/60) end
local s=mod.getStatus();assert(s.attemptsLastSecond==600 and s.acceptedLastSecond==300)
manual=false;frame(1.1);assert(mod.getStatus().acceptedLastSecond==0)
""")

    def test_expired_inflight_sample_cannot_leak_metrics(self):
        self.check('''
mode='CPF';rate=1
r.fireParry=function(_,guard) assert(guard());task.wait();return true end
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}));frame(.016)
tm=tm+2;assert(mod.getStatus().attemptsLastSecond==0)
manual=false;frame(.016)
assert(mod.getStatus().acceptedLastSecond==0,'expired in-flight sample leaked acceptance')
''')

if __name__=='__main__':unittest.main()
