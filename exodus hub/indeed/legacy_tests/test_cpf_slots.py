import unittest
import test_spaced_clicks as spacing

class CPFSlots(unittest.TestCase):
    def check(self, case):
        spacing.SpacedClicks().check('''
local jobs={}
task.delay=function(delay,fn,index) jobs[#jobs+1]={due=tm+delay,fn=fn,index=index} end
local function runDue()
 local pending=jobs;jobs={}
 for _,job in ipairs(pending) do
  if job.due<=tm then job.fn(job.index) else jobs[#jobs+1]=job end
 end
end
'''+case)

    def test_two_cpf_have_separate_slots_inside_one_frame(self):
        self.check('''
mode='CPF';rate=2;assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
assert(count==1 and #jobs==1)
local start=tm;tm=start+1/120;runDue()
assert(count==2 and #stamps==2)
assert(math.abs(stamps[2]-stamps[1]-1/120)<1e-9)
''')

    def test_late_slots_are_dropped_instead_of_bursting(self):
        self.check('''
mode='CPF';rate=10;assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
assert(count==1);tm=tm+.1;runDue();assert(count==1)
''')

    def test_cancelled_slots_cannot_send(self):
        self.check('''
mode='CPF';rate=2;assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
manual=false;tm=tm+1/120;runDue();assert(count==1)
''')
