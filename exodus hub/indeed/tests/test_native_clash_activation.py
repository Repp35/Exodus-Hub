"""Native clash is the sole entry; exercise real AutoSpam + Spam scheduler."""
import unittest
from pathlib import Path
from test_logic_reliability import run_case
from autospam_harness import COMMON, ENGINE, API
from test_logic_reliability import module

def check(case, extra):
 run_case(COMMON + ENGINE + module("autospam.luau").replace("local mod=", "local ap=", 1) + module("spam.luau").replace("local mod=", "local spam=", 1) + extra + API + case)

NATIVE = '''
local native=false;local nativeReads=0
g.getNativeClashContext=function() nativeReads=nativeReads+1;return native and {partnerId=99,lastParryAt=tm} or nil end
'''
class NativeClashTests(unittest.TestCase):
 def test_native_is_sufficient_without_target_or_window(self):
  check('''snap.targetId=-1;snap.targeted=false;snap.position=v(1000)
   native=true;ap.onDefenseOpportunity(snap)
   assert(ap.isActive());assert(ap.getActivationContext().reason=='native_clash')
   assert(clicks==1,'first send occurs in activation callback, no frame wait')
   assert(ap.canSend(),'no target confirmation gate')''',NATIVE)
 def test_old_activations_cannot_enter(self):
  check('''cfg.AutoSpamClashPrediction=true
   packet(99);animate(99,101);packet(42);heartbeat()
   assert(not ap.isActive());assert(clicks==0);assert(nativeReads>0)''',NATIVE)
 def test_native_false_is_not_a_new_deactivation_gate(self):
  check('''native=true;ap.onDefenseOpportunity(snap);assert(ap.isActive())
   native=false;packet(99);packet(42);heartbeat()
   assert(ap.isActive(),'existing deactivation policy owns exit')''',NATIVE)
 def test_cooldown_stops_and_cannot_immediately_reactivate(self):
  check('''native=true;ap.onDefenseOpportunity(snap)
   cd.blocking=true;cd.episode=1;cd.blockingSince=tm
   heartbeat(.5);assert(not ap.isActive(),'cooldown stops')
   for i=1,10 do ap.onDefenseOpportunity(snap) end
   assert(not ap.isActive(),'native flag cannot defeat cooldown')
   cd.blocking=false;ap.onDefenseOpportunity(snap);assert(ap.isActive())''',NATIVE)
 def test_distance_blocks_start_and_stops_before_next_send(self):
  check('''native=true;other.root.Position=v(50);ap.onDefenseOpportunity(snap);assert(not ap.isActive())
   other.root.Position=v(10);ap.onDefenseOpportunity(snap);assert(ap.isActive())
   local before=clicks;other.root.Position=v(50);assert(not ap.canSend());assert(not ap.isActive());assert(clicks==before)''',NATIVE)
 def test_only_ability_freeze_is_freeze(self):
  check('''native=true;snap.frozen=true;snap.velocity=v(0);ap.onDefenseOpportunity(snap);assert(ap.isActive(),'visual zero speed is not ability freeze')
   frozen=true;assert(not ap.canSend());assert(not ap.isActive())
   frozen=false;ap.onDefenseOpportunity(snap);assert(ap.isActive())''',NATIVE)
 def test_config_change_stops_synchronously(self):
  check('''native=true;ap.onDefenseOpportunity(snap);assert(ap.isActive())
   cfg.AutoSpam=false;configChanged:Fire({AutoSpam=false});assert(not ap.isActive())''',NATIVE)
 def test_hard_stops(self):
  for change in ("enabled=false", "me.hum.Health=0", "other.hum.Health=0", "world.attrs.MatchStatus=0", "snap.ball.Parent=nil", "snap.targetId=88;snap.targeted=false"):
   with self.subTest(change=change):
    check("native=true;ap.onDefenseOpportunity(snap);assert(ap.isActive());"+change+";assert(not ap.canSend());assert(not ap.isActive())",NATIVE)
 def test_attribute_event_activates_without_heartbeat(self):
  check('''native=true;world.changed:Fire();assert(ap.isActive());assert(clicks==1)''',NATIVE)
 def test_detach_cancels_attribute_and_scheduler_callbacks(self):
  check('''native=true;ap.onDefenseOpportunity(snap);ap.detachCharacter();local n=clicks
   world.changed:Fire();heartbeat();assert(not ap.isActive());assert(clicks==n)''',NATIVE)

class NativeProviderTests(unittest.TestCase):
 def test_actual_gameinfo_provider_calls_native_without_inferred_age_gate(self):
  source=(Path(__file__).resolve().parents[2]/'modules/logic/aux/gameinfo.luau').read_text()
  method=source[source.index('function GameInfo.getNativeClashContext()'):source.index('function GameInfo.getClashContext(')]
  run_case(r"""
   local reads,ready=0,true
   local player={UserId=42};local players={LocalPlayer=player}
   local world={attrs={LastParryBy=99,LastParryTarget=42,LastParryAt=-100}}
   function world:GetAttribute(k) return self.attrs[k] end
   local gameBall={IsInClash=function(_,p) assert(p==player);reads=reads+1;return ready end}
   local GameInfo={getBallSpeedLimits=function() return 16,600 end}
   local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
  """+method+r"""
   assert(GameInfo.getNativeClashContext().partnerId==99);assert(reads==1)
   world.attrs.LastParryBy=42;world.attrs.LastParryTarget=99
   assert(GameInfo.getNativeClashContext().partnerId==99)
   ready=false;assert(GameInfo.getNativeClashContext()==nil)
   ready=true;world.attrs.LastParryTarget=42;assert(GameInfo.getNativeClashContext()==nil)
  """)

if __name__=='__main__':unittest.main()
