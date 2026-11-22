"""Native clash plus the shared 0.9 window control entry; exercise real AutoSpam + Spam scheduler."""
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
g.getClashStatus=function() local c=g.getNativeClashContext();return {active=c~=nil,partnerId=c and c.partnerId} end
'''
class NativeClashTests(unittest.TestCase):
 def test_native_inside_window_is_sufficient_without_target(self):
  check('''snap.targetId=-1;snap.targeted=false;snap.position=v(50)
   native=true;ap.onDefenseOpportunity(snap)
   assert(ap.isActive());assert(ap.getActivationContext().reason=='native_clash')
   assert(clicks==1,'first send occurs in activation callback, no frame wait')
   assert(ap.canSend(),'no target confirmation gate')''',NATIVE)
 def test_window_boundary_blocks_entry_and_cuts_before_send(self):
  check('''local old=g.getDeflectGeometry
   g.getDeflectGeometry=function(speed,mode,factor,...) return old(speed,mode,factor,...) end
   local radius=old(600,"game",.9).fullRadius+600*(.65*.20)*.9
   native=true;snap.position=v(radius+.001);ap.onDefenseOpportunity(snap);assert(not ap.isActive())
   snap.position=v(radius);ap.onDefenseOpportunity(snap);assert(ap.isActive(),'boundary inclusive')
   local n=clicks;snap.position=v(radius+.001);assert(not ap.canSend());assert(not ap.isActive());assert(clicks==n)
   ap.onDefenseOpportunity(snap);assert(not ap.isActive(),'cannot reactivate outside')
   snap.position=v(radius-.001);ap.onDefenseOpportunity(snap);assert(ap.isActive(),'return inside renews entry')''',NATIVE)
 def test_window_exit_event_and_invalid_input_stop(self):
  for change in ('snap.position=v(1000)', 'snap.position=v(0/0)', 'snap.syncAt=tm-1', 'snap.syncSpeed=0/0'):
   with self.subTest(change=change):
    check('native=true;ap.onDefenseOpportunity(snap);assert(ap.isActive());'+change+';ap.onDefenseOpportunity(snap);assert(not ap.isActive())',NATIVE)
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

class ExodusClashStatusTests(unittest.TestCase):
 def test_local_rules_and_live_settings_without_native_calls(self):
  source=(Path(__file__).resolve().parents[2]/'modules/logic/aux/gameinfo.luau').read_text()
  method=source[source.index('function GameInfo.getClashStatus('):source.index('function GameInfo.getClashContext(')]
  run_case(COMMON+ENGINE+r"""
   local utils=u
   local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
   local GameInfo={}
   local gameBall={IsInClash=function() error('must never call native') end}
   world.attrs.LastParryAt=tm;world.attrs.LastParryBy=42;world.attrs.LastParryTarget=99
  """+method+r"""
   assert(GameInfo.IsInClash(),'one valid parry suffices')
   world.attrs.GameBallTarget=88;assert(GameInfo.getClashStatus().reason=='redirected')
   world.attrs.GameBallTarget=nil;assert(GameInfo.IsInClash(),'missing target is not a third player')
   other.hum.Health=0;assert(GameInfo.getClashStatus().reason=='player_dead')
   other.hum.Health=100;assert(GameInfo.IsInClash())
   world.attrs.LastParryTarget=99.5;assert(not GameInfo.IsInClash())
   world.attrs.LastParryTarget=99
   assert(GameInfo.getClashStatus().source=='exodus')
   world.attrs.LastParryAt=tm-1.1;world.attrs.GameBallTarget=42
   assert(GameInfo.getClashStatus().reason=='target_changed')
   world.attrs.GameBallTarget=99;assert(GameInfo.IsInClash())
   world.attrs.LastParryAt=tm-2.6;assert(not GameInfo.IsInClash())
   world.attrs.LastParryAt=tm;other.root.Position=v(35);assert(GameInfo.IsInClash())
   other.root.Position=v(35.01);assert(not GameInfo.IsInClash())
   cfg.ClashMaxDistance=20;other.root.Position=v(21);assert(not GameInfo.IsInClash())
   other.root.Position=v(10);world.attrs.LastParryAt=tm-.6;cfg.ClashMaxAge=.5
   assert(not GameInfo.IsInClash())
   cfg.ClashMaxAge=2.5;cfg.ClashGrace=.3;world.attrs.GameBallTarget=42
   assert(not GameInfo.IsInClash())
   world.attrs.LastParryAt=tm+.1;assert(not GameInfo.IsInClash())
  """)

if __name__=='__main__':unittest.main()
