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
        source=(ROOT/'autoparry.luau').read_text()
        code=source[source.index('local function matchTiming('):source.index('-- target-sync')]
        run_case(COMMON+'''
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function vector(x) return typeof(x)=='Vector3' end
local function validBallSpeed(x) return finite(x) and x>=0 and x<=1000 end
local function activeWindowFactor() return .3 end
local function radius() return {fullRadius=30,noWindowParryRadius=8.5,windowFactor=.3} end
local deflectGeometry={getKillRadius=function() return 4 end}
'''+code+'''
for _,velocity in ipairs({v(-100),v(100),v(0,100),v()}) do
 local result=matchTiming({position=v(20),velocity=velocity,speed=100},tm,v())
 assert(result.ready,'velocity vetoed an in-range ball')
end
''')
