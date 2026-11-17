"""Literal 200 ms return + two observed exit/reentry pairs; exclusive 100 ms stop."""
import unittest
from test_logic_reliability import COMMON,module,run_case
from autospam_harness import check
SETUP='''
local detector=mod.new();local ball={}
local function sample(at,target,distance,patch)
 local s={at=at,ball=ball,targetId=target,me=42,distance=distance,fullRadius=20,
 killRadius=4,inWindow=true,partnerId=99}
 for k,v in pairs(patch or {}) do s[k]=v end
 return detector.observe(s)
end
'''
class ReturnKillCycles(unittest.TestCase):
 def check(self,case):run_case(COMMON+module('aux/returnkill.luau')+SETUP+case)
 def test_two_complete_pairs_activate_inside_one_fixed_timer(self):
  self.check('''sample(0,42,3);sample(.02,99,10);assert(not sample(.06,42,3))
sample(.10,99,10);local r=sample(.14,42,3)
assert(r and r.cycles==2 and r.elapsed<.2)''')
 def test_no_departure_no_timer(self):
  self.check('''sample(0,42,3);sample(.02,42,10);sample(.04,42,3)
sample(.06,42,10);assert(not sample(.08,42,3))''')
 def test_timer_cannot_start_outside_window(self):
  self.check('''sample(0,42,3,{inWindow=false});sample(.02,99,10);sample(.04,42,3)
sample(.06,99,10);assert(not sample(.08,42,3))''')
 def test_timer_is_not_renewed_on_another_departure(self):
  self.check('''sample(0,42,3);sample(.02,99,10);sample(.10,42,3)
sample(.19,99,10);assert(not sample(.23,42,3))''')
 def test_first_return_outside_full_radius_does_not_qualify_later_by_proximity(self):
  self.check('''sample(0,42,3);sample(.02,99,10);sample(.04,42,21)
sample(.06,42,3);sample(.08,42,10);assert(not sample(.10,42,3))''')
 def test_repeated_inside_samples_are_not_crossings(self):
  self.check('''sample(0,42,3);sample(.02,99,10);sample(.04,42,3)
for i=5,15 do assert(not sample(i/100,42,3)) end''')
 def test_target_and_window_required_on_activation(self):
  self.check('''sample(0,42,3);sample(.02,99,10);sample(.04,42,3);sample(.06,99,10)
assert(not sample(.08,99,3));assert(not sample(.09,42,3,{inWindow=false}))''')
 def test_ball_replacement_and_reset_clear_cycles(self):
  self.check('''sample(0,42,3);sample(.02,99,10);sample(.04,42,3);sample(.06,99,10)
assert(not sample(.08,42,3,{ball={}}))
detector.reset();assert(not sample(.1,42,3))''')

EXTRA=module('aux/returnkill.luau').replace('local mod=','local rk=',1)
PRIME='''
assert(ap.setup({Utils=u,GameInfo=g,Cooldown=c,ClashStats=st,Dash=d,ReturnKill=rk}))
assert(ap.bindCharacter(me.Character));other.root.Position=v(80)
packet(42,0,3);packet(99,.02,10);packet(42,.04,3)
assert(not ap.isActive());packet(99,.04,10);packet(42,.04,3)
assert(ap.isActive() and ap.getActivationContext().reason=='return_kill_cycles')
'''
class ReturnKillIntegration(unittest.TestCase):
 def check(self,case):check(PRIME+case,EXTRA)
 def test_exclusive_timeout_bypasses_old_14_stud_protection(self):
  self.check('''other.root.Position=v(13);advance(.101)
assert(not ap.canSend() and not ap.isActive())
assert(ap.getStatus().lastStopReason=='return_exchange_timeout')''')
 def test_each_genuine_swap_refreshes_100ms(self):
  self.check('''other.root.Position=v(13)
for i=1,20 do packet(i%2==1 and 99 or 42,.08,3);assert(ap.isActive()) end''')
 def test_same_target_updates_do_not_refresh_timer(self):
  self.check('''other.root.Position=v(13)
for i=1,6 do packet(42,.02,3) end
assert(not ap.isActive())''')
 def test_five_stud_exception_and_leaving_exception(self):
  self.check('''other.root.Position=v(5);heartbeat(.15);assert(ap.isActive() and ap.canSend())
other.root.Position=v(5.01);assert(not ap.canSend())''')
 def test_third_player_does_not_refresh_local_pair_timer(self):
  self.check('''other.root.Position=v(13);third.root.Position=v(15)
packet(88,.06,3);advance(.05);assert(not ap.canSend())''')
 def test_exclusive_timeout_does_not_apply_to_original_gate(self):
  check('''packet(42,0,2);other.root.Position=v(13)
assert(ap.getActivationContext().reason=='close_target');heartbeat(.2)
assert(ap.isActive())''')
 def test_gate_never_reads_ap(self):
  self.check('''defender.getPressureDetector=function() error('must not access AP') end
other.root.Position=v(13);packet(99,.04,3);assert(ap.isActive())''')
 def test_timed_out_activation_cannot_reuse_consumed_crossings(self):
  check('''assert(ap.setup({Utils=u,GameInfo=g,Cooldown=c,ClashStats=st,Dash=d,ReturnKill=rk}))
assert(ap.bindCharacter(me.Character));other.root.Position=v(80)
packet(42,0,3);packet(99,.005,10);packet(42,.005,3);packet(99,.005,10);packet(42,.005,3)
assert(ap.isActive());other.root.Position=v(80)
advance(.101);assert(not ap.canSend());heartbeat(.021)
assert(not ap.isActive(),'old kill crossings reactivated expired session')''',EXTRA)

if __name__=='__main__':unittest.main()
