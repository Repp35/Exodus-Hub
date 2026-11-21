"""AP authorization outcomes, without freezing the implementation's gates."""
import unittest
from test_targeting import check
from test_logic_reliability import COMMON, ROOT, run_case

class TargetAuthorization(unittest.TestCase):
    def test_old_red_color_cannot_click_for_an_opponent(self):
        check("ball.Color=red;local r=resolver.resolve(context);assert(not r.targeted and r.targetId==99)")

    def test_old_positive_provider_cannot_override_current_target(self):
        check("provider.IsLocalTarget=function() return true end;local r=resolver.resolve(context);assert(not r.targeted and r.targetId==99)")

    def test_current_local_target_is_recognized(self):
        check("context.sync.TargetPlayerID=42;world.attrs.GameBallTarget=42;local r=resolver.resolve(context);assert(r.known and r.targeted and r.targetId==42)")

    def test_visual_fallback_without_target_metadata(self):
        check("context.syncFresh=false;world.attrs.GameBallTarget=nil;other.Character.children.PlayerBallHighlight=nil;me.Character.children.PlayerBallHighlight=highlight;ball.Color=red;local r=resolver.resolve(context);assert(r.known and r.targeted)")

    def test_range_decision_accepts_all_directions(self):
        from test_defenseengine import STACK
        run_case(STACK+r'''
for _,velocity in ipairs({v(-100),v(100),v(0,100),v()}) do
 local result=geom.getParryTiming({position=v(8),velocity=velocity,speed=100},v(),{factor=.3,ping=0})
 assert(result.ready,'velocity vetoed physical parry range')
end
local incoming=geom.getParryTiming({position=v(20),velocity=v(-100),speed=100},v(),{factor=.3,ping=0})
assert(incoming.ready,'window extension lost incoming ball')
''')
