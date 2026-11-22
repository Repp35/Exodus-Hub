import unittest
import test_autospam_lifecycle_v6 as lifecycle
from test_logic_reliability import COMMON, module, run_case
from autospam_harness import ENGINE, API

class IndependentActivation(unittest.TestCase):
 def case(self, script):
  lifecycle.AutoSpamLifecycleV6().case(script)
 def test_native_before_contact_without_target_history_or_fast_return(self):
  self.case('''native=true;third.root.Position=v(200);third.root.Position=v(200);other.root.Position=v(25);snap.position=v(95);snap.velocity=v(-600);snap.targetId=99
ap.onDefenseOpportunity(snap);assert(ap.isActive());assert(clicks==1)
assert(ap.getActivationContext().reason=='native_clash');assert(ap.getStatus().gates.native=='ready')
assert(ap.getStatus().gates.fastReturn=='no_return_evidence')
''')
 def test_fast_return_works_with_native_unavailable(self):
  self.case('''native=false;packet(42,0,5);packet(99,.01,5);packet(42,.01,5)
assert(ap.isActive());assert(ap.getActivationContext().reason=='fast_return')
assert(ap.getStatus().gates.native=='no_clash_partner');assert(ap.getStatus().gates.fastReturn=='ready')
''')
 def test_both_ready_are_evaluated_without_first_gate_short_circuit(self):
  self.case('''native=false;packet(42,0,500);packet(99,.01,500);packet(42,.01,500)
native=true;snap.position=v(5);ap.onDefenseOpportunity(snap)
assert(ap.isActive());assert(ap.getStatus().gates.native=='ready');assert(ap.getStatus().gates.fastReturn=='ready')
assert(ap.getActivationContext().reason=='native_clash')
''')
 def test_production_clash_status_drives_native_entry(self):
  from test_raw_target_parry import ROOT
  raw=(ROOT/'aux/gameinfo.luau').read_text()
  status=raw[raw.index('function GameInfo.getClashStatus('):raw.index('function GameInfo.IsInClash')]
  self.case('''local GameInfo={};local world=world;local players=players
local function finite(x) return type(x)=='number' and x==x and x<math.huge and x>-math.huge end
'''+status+'''
g.getClashStatus=GameInfo.getClashStatus
world.attrs.LastParryBy=42;world.attrs.LastParryTarget=99;world.attrs.LastParryAt=tm;world.attrs.GameBallTarget=99;world.attrs.ClashHits=2
third.root.Position=v(200);other.root.Position=v(25);snap.position=v(95);snap.velocity=v(-600);snap.targetId=99
ap.onDefenseOpportunity(snap);assert(ap.isActive());assert(clicks==1);assert(ap.getActivationContext().reason=='native_clash')
''')
