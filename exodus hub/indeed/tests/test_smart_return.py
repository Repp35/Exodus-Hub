"""Real isolated gate: return context, radius, historical depth and sensitivity."""
import unittest
from test_logic_reliability import COMMON,module,run_case

SETUP='''
local gate=mod.new();local ball={}
local function sample(t,target,distance,patch)
 local s={at=t,ball=ball,targetId=target,me=42,distance=distance,fullRadius=20,killRadius=4,
 partnerId=99,partnerDistance=13,sensitivity=50}
 for k,v in pairs(patch or {}) do s[k]=v end
 return gate.observe(s)
end
local function departure(minimum)
 sample(0,42,20);sample(.01,42,minimum);sample(.02,99,20)
end
'''
class SmartReturn(unittest.TestCase):
 def check(self,case):run_case(COMMON+module('aux/smartreturn.luau')+SETUP+case)
 def test_no_context_never_activates(self):
  self.check('''assert(not sample(0,42,5));assert(not sample(.01,42,4))
gate.reset();sample(0,99,20);assert(not sample(.05,42,5))''')
 def test_deep_previous_parry_and_fast_real_return(self):
  self.check('''departure(8);local r=sample(.20,42,20)
assert(r and math.abs(r.returnTime-.18)<.0001 and r.budget==.2)''')
 def test_precise_previous_parry_does_not_become_spam(self):
  self.check('''departure(20);assert(not sample(.06,42,20))''')
 def test_slow_return_rejected_even_at_kill_radius(self):
  self.check('''departure(5);assert(not sample(.23,42,4))''')
 def test_close_partner_expands_current_radius_only_twenty_percent(self):
  self.check('''departure(8);assert(sample(.12,42,23))
gate.reset();departure(8);assert(not sample(.12,42,24.01))
gate.reset();departure(8);assert(not sample(.12,42,23,{partnerDistance=16}))''')
 def test_previous_visit_must_enter_its_full_radius(self):
  self.check('''sample(0,42,30);sample(.02,99,30);assert(not sample(.1,42,5))''')
 def test_deepening_visits_raise_pressure(self):
  self.check('''departure(15);assert(not sample(.21,42,20))
sample(.22,42,13);sample(.23,99,20);local r=sample(.42,42,20)
assert(r and r.worsening>0)''')
 def test_sensitivity_changes_threshold_and_return_tolerance(self):
  self.check('''departure(14);assert(not sample(.17,42,20,{sensitivity=0}))
gate.reset();departure(14);assert(sample(.17,42,20,{sensitivity=100}))''')
 def test_current_ap_dispatch_prevents_late_extra_activation(self):
  self.check('''departure(8);assert(not sample(.12,42,30))
assert(not sample(.13,42,20,{apAt=.125,apDistance=19}))''')
 def test_third_player_can_return_after_local_departure(self):
  self.check('''departure(8);sample(.07,88,20);assert(sample(.15,42,20,{partnerId=88}))''')
 def test_reset_reused_ball_and_clock_reversal_clear_context(self):
  self.check('''departure(8);gate.reset();assert(not sample(.1,42,4))
gate.reset();departure(8);assert(not sample(.1,42,4,{ball={}}))
gate.reset();departure(8);assert(not sample(-1,42,4))''')
 def test_reference_time_is_independent_of_speed(self):
  for speed in (16,100,600):self.check(f'''departure(8);assert(sample(.2,42,20,{{speed={speed}}}).budget==.2)''')

class SmartReturnIntegration(unittest.TestCase):
 def check(self,case):
  from autospam_harness import check
  extra=module('aux/smartreturn.luau').replace('local mod=','local smart=',1)
  check('''g.getAutoParryGeometry=function() return {fullRadius=20} end
assert(ap.setup({Utils=u,GameInfo=g,Cooldown=c,ClashStats=st,Dash=d,SmartReturn=smart,AutoParry=defender}))
assert(ap.bindCharacter(me.Character));other.root.Position=v(80)
'''+case,extra)
 def test_real_auto_spam_activates_only_after_required_return(self):
  self.check('''packet(42,0,20);packet(42,.01,8);assert(not ap.isActive())
packet(99,.01,20);assert(not ap.isActive())
packet(42,.18,20)
assert(ap.isActive() and ap.getActivationContext().reason=='smart_return')
assert(clicks==1)''')
 def test_real_sender_does_not_add_click_after_current_ap_dispatch(self):
  self.check('''packet(42,0,20);packet(42,.01,8);packet(99,.01,20)
packet(42,.1,30);assert(not ap.isActive())
clicks=clicks+1;defense.lastAcceptedSample={ball=ball,at=tm+.001,distance=20,idealDistance=20}
packet(42,.01,20)
assert(not ap.isActive() and clicks==1)''')
 def test_real_snapshot_reset_clears_gate_context(self):
  self.check('''packet(42,0,20);packet(42,.01,8);packet(99,.01,20)
snap.teleported=true;heartbeat(.01);snap.teleported=false
packet(42,.1,20);assert(not ap.isActive())''')

if __name__=='__main__':unittest.main()
