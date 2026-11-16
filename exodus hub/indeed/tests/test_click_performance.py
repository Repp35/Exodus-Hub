"""Click rate, cancellation and metrics for the allocation-light scheduler."""
import unittest
from test_logic_reliability import COMMON, SPAM, module, run_case

class ClickPerformance(unittest.TestCase):
    def check(self,case):
        run_case(COMMON+SPAM+module('spam.luau')+case)

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

    def test_final_validation_rejects_changed_state_inside_same_burst(self):
        self.check("""
mode='CPF';rate=100;local domain=true;local attempted=0
local errors=0;u.recordError=function() errors=errors+1 end
a.canSendManual=function() return domain end
r.prepareParry=function(guard) return function()
 attempted=attempted+1;if not guard() then return false,'Deflect cancelado' end
 count=count+1;domain=false;return true
end end
assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}));frame(.016)
assert(count==1 and attempted==2,'burst continued after final validation failed')
""")

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
