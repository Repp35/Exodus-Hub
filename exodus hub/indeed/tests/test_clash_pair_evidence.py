import unittest
from pathlib import Path
import test_autospam_lifecycle_v6 as lifecycle
from test_raw_target_parry import ROOT

class ClashPairEvidence(unittest.TestCase):
 def test_proximity_without_pair_history_never_activates(self):
  source=(ROOT/'aux/gameinfo.luau').read_text()
  method=source[source.index('function GameInfo.getClashStatus('):source.index('function GameInfo.IsInClash')]
  lifecycle.AutoSpamLifecycleV6().case('''
local GameInfo={};local function finite(x) return type(x)=='number' and x==x and x<math.huge and x>-math.huge end
local gameBall={IsInClash=function() error('native IsInClash must never be called') end}
''' + method + '''
g.getClashStatus=GameInfo.getClashStatus
snap.position=v(5);other.root.Position=v(5);third.root.Position=v(7)
world.attrs.LastParryAt=nil;ap.onDefenseOpportunity(snap);assert(not ap.isActive())
world.attrs.LastParryAt=tm;world.attrs.LastParryBy=42;world.attrs.LastParryTarget=99
for _,hits in ipairs({0}) do world.attrs.ClashHits=hits;ap.onDefenseOpportunity(snap);assert(not ap.isActive());assert(GameInfo.getClashStatus(10).reason=='no_pair_exchange') end
world.attrs.ClashHits=1;snap.targetId=99;snap.position=v(2);snap.velocity=v(-600);world.attrs.GameBallTarget=99
ap.onDefenseOpportunity(snap);assert(not ap.isActive(),'one parry without confirmed direction must not activate')
snap.velocity=v(600);advance(.01);snap.syncAt=tm;world.attrs.LastParryAt=tm
ap.onDefenseOpportunity(snap);assert(ap.isActive(),'first confirmed outward parry should activate');ap.stopSpam('test');snap.position=v(5);snap.velocity=v(-600)
world.attrs.ClashHits=2;world.attrs.LastParryBy=99;world.attrs.LastParryTarget=88
ap.onDefenseOpportunity(snap);assert(not ap.isActive());assert(GameInfo.getClashStatus(10).reason=='not_in_pair')
world.attrs.LastParryBy=42;world.attrs.LastParryTarget=99;world.attrs.GameBallTarget=88
ap.onDefenseOpportunity(snap);assert(not ap.isActive());assert(GameInfo.getClashStatus(10).reason=='third_target')
world.attrs.GameBallTarget=99;world.attrs.LastParryAt=tm-1
ap.onDefenseOpportunity(snap);assert(not ap.isActive());assert(GameInfo.getClashStatus(10).reason=='expired')
world.attrs.LastParryAt=tm;world.attrs.ClashHits=2;world.attrs.LastParryBy=99;world.attrs.LastParryTarget=42;world.attrs.GameBallTarget=42
ap.onDefenseOpportunity(snap);assert(ap.isActive());assert(ap.getActivationContext().reason=='native_clash')
''')
