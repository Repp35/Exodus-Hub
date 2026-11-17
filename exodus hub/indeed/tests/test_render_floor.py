"""Validate the explicit render floor and conservative map visibility."""
import unittest
from test_raw_target_parry import ROOT, run_lua

class RenderFloor(unittest.TestCase):
    def test_only_parts_entirely_below_floor_are_hidden(self):
        source=(ROOT/'extras/antilag.luau').read_text()
        code=source[source.index('local function verticalDecision('):source.index('local function createSpatialController(')]
        code=code.replace('(if previous == "above" then margin else 0)', '(previous == "above" and margin or 0)').replace('(if previous == "below" then margin else 0)', '(previous == "below" and margin or 0)')
        run_lua(code+'''
local options={CullVertical=false,CullFloorY=95}
assert(verticalDecision(80,94,150,nil,options)=='floor')
assert(verticalDecision(90,96,150,nil,options)==nil,'floor hid intersecting geometry')
assert(verticalDecision(95,96,150,nil,options)==nil)
options.CullFloorY=nil; assert(verticalDecision(-100,0,150,nil,options)==nil)
''')

if __name__ == '__main__': unittest.main()

class CameraCulling(unittest.TestCase):
    def check(self, case):
        from test_logic_reliability import COMMON
        source=(ROOT/'extras/antilag.luau').read_text()
        code=source[source.index('local function verticalDecision('):source.index('local function createSpatialController(')]
        code=code.replace('(if previous == "above" then margin else 0)', '(previous == "above" and margin or 0)').replace('(if previous == "below" then margin else 0)', '(previous == "below" and margin or 0)')
        run_lua(COMMON+'''
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
'''+code+'''
local view={position=v(),look=v(0,0,1),right=v(1,0,0),up=v(0,1,0),options={
 CullDistance=128,CullRestoreMargin=8,CullKeepNear=16,CullView=true,CullViewPadding=12,
 CullHideDelay=.15,ViewTanX=1,ViewTanY=1,CullVertical=false,CullFloorY=-5}}
view.planes=cameraPlanes(view)
local half=v(1,1,1)
'''+case)

    def test_visible_below_floor_and_view_margin_are_retained(self):
        self.check('''
assert(renderDecision(v(0,-20,40),half,nil,nil,10,view,false)==nil)
assert(renderDecision(v(0,-50,20),half,nil,nil,10,view,false)=='floor')
assert(renderDecision(v(35,0,30),half,nil,1,10,view,false)==nil,'margin disappeared')
assert(renderDecision(v(100,0,30),half,nil,1,10,view,false)=='view')
view.look=v(0,-1,0);view.up=v(0,0,1);view.planes=cameraPlanes(view)
assert(renderDecision(v(0,-50,20),half,'floor',1,11,view,false)==nil,'looking down failed to restore visible geometry')
''')

    def test_clash_cube_is_centered_on_player_and_keeps_intersecting_parts(self):
        self.check('''
view.options.ClashCenter=v();view.options.ClashFloorY=-5
assert(renderDecision(v(0,0,61),half,nil,nil,10,view,false)==nil)
assert(renderDecision(v(0,0,62),half,nil,nil,10,view,false)=='clash_cube')
assert(renderDecision(v(0,-20,40),half,nil,nil,10,view,false)=='clash_floor')
view.options.ClashCenter=nil;view.options.ClashFloorY=nil
assert(renderDecision(v(0,0,62),half,'clash_cube',nil,11,view,false)==nil)
assert(renderDecision(v(0,0,127),half,'distance',nil,11,view,false)==nil,'distance hysteresis hid an object inside the configured range')
''')

    def test_floor_history_only_descends_when_grounded_and_resets_on_respawn(self):
        source=(ROOT/'extras/antilag.luau').read_text()
        code=source[source.index('    GetFloorY = function()'):source.index('    GetClashBounds = function()')]
        run_lua('''
Enum={Material={Air='air'}}
local owner={};local enabled=true
local function setting(key) return key=='AntiLagFloorCull' and enabled end
local root={Position={Y=100},Size={Y=2}}
local humanoid={Health=100,FloorMaterial='grass',HipHeight=2}
local function character() return {FindFirstChild=function() return root end,FindFirstChildOfClass=function() return humanoid end} end
local player={Character=character()}
local services={
'''+code+'''
}
assert(services.GetFloorY()==92)
root.Position.Y=110;assert(services.GetFloorY()==92)
root.Position.Y=90;assert(services.GetFloorY()==82)
humanoid.FloorMaterial='air';root.Position.Y=60;assert(services.GetFloorY()==82)
player.Character=character();humanoid.FloorMaterial='grass';root.Position.Y=100
assert(services.GetFloorY()==92)
enabled=false;assert(services.GetFloorY()==nil)
''')

    def test_clash_bounds_exit_when_native_clash_ends(self):
        source=(ROOT/'extras/antilag.luau').read_text()
        code=source[source.index('    GetClashBounds = function()'):source.index('    OnHidden = function(')]
        run_lua('''
local enabled=true
local function setting() return enabled end
local physics={clashKnown=true,inClash=false}
local DeflectGeometry={getDefensePhysics=function() return physics end}
local AutoSpam={isActive=function() return true end}
local root={Position={Y=10}};local player={Character={FindFirstChild=function() return root end}}
local owner={currentFloorY=7,closed=false}
local services={
'''+code+'''
}
assert(services.GetClashBounds()==nil,'old AutoSpam activity kept native-ended clash mode enabled')
physics.inClash=true;local center,floor=services.GetClashBounds();assert(center==root.Position and floor==2)
physics.inClash=false;physics.clashKnown=false;assert(services.GetClashBounds()==root.Position)
enabled=false;assert(services.GetClashBounds()==nil)
''')
