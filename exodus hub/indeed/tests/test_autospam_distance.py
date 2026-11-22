"""Opponent range follows the local parry radius with an eleven stud floor."""
import unittest
from test_raw_target_parry import ROOT, run_lua

class AutoSpamDistance(unittest.TestCase):
    def test_radius_floor_and_invalid_geometry(self):
        source = (ROOT / 'autospam.luau').read_text()
        helper = source[source.index('local function opponentDistanceLimit('):source.index('local function insideSpamWindow(')]
        run_lua("""
math.clamp=function(x,a,b) return math.max(a,math.min(b,x)) end
local CONFIG={ACTIVATION={MIN_CLASH_DISTANCE=11}}
local function finite(x) return type(x)=='number' and x==x and x<math.huge and x>-math.huge end
local function snapshotSpeed(s) return s and s.speed end
local function frameLead() return 1/60 end
local utils={getConfigValue=function(k) assert(k=='AutoParryWindowFactor');return .3 end}
local gameInfo={getAveragePing=function() return .04 end}
local radius=25
local deflectGeometry={getAutoParryGeometry=function(speed,factor,frame,ping)
 assert(speed==600 and factor==.3 and frame==1/60 and ping==.04)
 return radius~=nil and {fullRadius=radius} or nil
end}
""" + helper + """
local s={speed=600}
assert(opponentDistanceLimit({},s)==25)
radius=7;assert(opponentDistanceLimit({},s)==11)
radius=80;assert(opponentDistanceLimit({},s)==80)
for _,v in ipairs({0/0,math.huge,-math.huge,-2}) do radius=v;assert(opponentDistanceLimit({},s)==11) end
radius=nil;assert(opponentDistanceLimit({},s)==11)
assert(opponentDistanceLimit({},nil)==11)
""")
