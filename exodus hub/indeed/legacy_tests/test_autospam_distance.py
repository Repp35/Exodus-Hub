"""Clash distance is the local full radius, with no floor."""
import unittest
from test_raw_target_parry import ROOT, run_lua

class AutoSpamDistance(unittest.TestCase):
 def test_local_full_radius_with_ten_stud_floor_and_invalid_geometry(self):
  source=(ROOT/'combat/autospam.luau').read_text()
  helper=source[source.index('local function opponentDistanceLimit('):source.index('local function insideSpamWindow(')]
  run_lua('''
math.clamp=function(x,a,b) return math.max(a,math.min(b,x)) end
local function finite(x) return type(x)=='number' and x==x and x<math.huge and x>-math.huge end
local function snapshotSpeed(s) return s and s.speed end
local function frameLead() return 1/60 end
local utils={getConfigValue=function() return .3 end}
local gameInfo={getAveragePing=function() return .04 end}
local ownRadius,otherRadius=25,10
local deflectGeometry={getAutoParryGeometry=function(speed,factor,frame,ping,id)
 assert(speed==600 and factor==.3 and frame==1/60 and ping==.04)
 assert(id==nil,'opponent radius must not be read')
 return {fullRadius=id and otherRadius or ownRadius}
end}
''' + helper + '''
local s={speed=600}
assert(opponentDistanceLimit({},s,99)==25)
ownRadius=3;otherRadius=4;assert(opponentDistanceLimit({},s,99)==10)
ownRadius=0;otherRadius=0;assert(opponentDistanceLimit({},s,99)==10)
for _,bad in ipairs({0/0,math.huge,-math.huge,-2}) do ownRadius=bad;assert(opponentDistanceLimit({},s,99)==0) end
ownRadius=25;otherRadius=-1;assert(opponentDistanceLimit({},s,99)==25)
assert(opponentDistanceLimit({},nil,99)==0)
assert(opponentDistanceLimit({},s,nil)==25)
''')

 def test_own_radius_boundary_and_outside_stop_with_ten_stud_floor(self):
  import test_autospam_lifecycle_v6 as lifecycle
  lifecycle.AutoSpamLifecycleV6().case('''
g.getAutoParryGeometry=function(speed,factor,frame,ping,id)
 return {fullRadius=id and 4 or 3,effectiveWindow=.1,noWindowParryRadius=3}
end
native=true;snap.position=v(3);snap.velocity=v(-600);other.root.Position=v(10.001)
ap.onDefenseOpportunity(snap);assert(not ap.isActive(),'outside own radius must block even below 11 studs')
other.root.Position=v(10);ap.onDefenseOpportunity(snap);assert(ap.isActive(),'ten stud floor boundary must permit activation')
other.root.Position=v(10.001);assert(not ap.canSend());assert(not ap.isActive())
''')
