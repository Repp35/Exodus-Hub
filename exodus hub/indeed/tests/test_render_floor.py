"""Validate the explicit render floor and conservative map visibility."""
import unittest
from test_raw_target_parry import ROOT, run_lua

class RenderFloor(unittest.TestCase):
    def test_parts_crossing_floor_are_hidden(self):
        source=(ROOT/'extras/antilag.luau').read_text()
        code=source[source.index('local function verticalDecision('):source.index('local function createSpatialController(')]
        code=code.replace('(if previous == "above" then margin else 0)', '(previous == "above" and margin or 0)').replace('(if previous == "below" then margin else 0)', '(previous == "below" and margin or 0)')
        run_lua(code+'''
local options={CullVertical=false,CullFloorY=95}
assert(verticalDecision(80,94,150,nil,options)=='floor')
assert(verticalDecision(90,96,150,nil,options)=='floor','floor retained intersecting geometry')
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
 CullDistance=128,CullKeepNear=16,CullView=true,CullViewPadding=12,
 CullHideDelay=.15,ViewTanX=1,ViewTanY=1,CullVertical=false,CullFloorY=-5}}
view.planes=cameraPlanes(view)
local half=v(1,1,1)
'''+case)

    def test_floor_applies_even_when_visible_and_turning(self):
        self.check('''
assert(renderDecision(v(0,-20,40),half,nil,nil,10,view,false)=='floor')
assert(renderDecision(v(0,-50,20),half,nil,nil,10,view,false)=='floor')
assert(renderDecision(v(35,0,30),half,nil,1,10,view,false)==nil,'margin disappeared')
assert(renderDecision(v(100,0,30),half,nil,1,10,view,false)=='view')
view.look=v(0,-1,0);view.up=v(0,0,1);view.planes=cameraPlanes(view)
assert(renderDecision(v(0,-50,20),half,'floor',1,11,view,false)=='floor','looking down bypassed floor')
assert(renderDecision(v(0,-50,20),half,nil,nil,11,view,true)=='floor','turn bypassed floor')
''')

    def test_distance_has_no_extra_margin_even_when_visible_or_turning(self):
        self.check('''
view.options.CullDistance=200
assert(renderDecision(v(0,0,202),half,nil,nil,10,view,false)=='distance')
assert(renderDecision(v(0,0,202),half,nil,nil,10,view,true)=='distance','turn hold bypassed range')
assert(renderDecision(v(0,0,200),half,'distance',nil,11,view,false)=='distance')
assert(renderDecision(v(0,0,198),half,'distance',nil,11,view,false)==nil)
view.focus=v(0,0,100)
assert(renderDecision(v(0,0,250),half,'distance',nil,12,view,false)==nil,'range did not follow player')
assert(renderDecision(v(0,0,302),half,nil,nil,12,view,false)=='distance')
''')

    def test_floor_follows_current_character_and_ignores_saved_toggle(self):
        source=(ROOT/'extras/antilag.luau').read_text()
        code=source[source.index('    GetFloorY = function()'):source.index('    GetFocusPosition = function()')]
        run_lua('''
local root={Position={Y=100},Size={Y=2}}
local humanoid={Health=100,HipHeight=2}
local player={Character={FindFirstChild=function() return root end,FindFirstChildOfClass=function() return humanoid end}}
local function viewedCharacter() return player.Character end
local services={
'''+code+'''
}
assert(services.GetFloorY()==95)
root.Position.Y=110;assert(services.GetFloorY()==105)
root.Position.Y=60;assert(services.GetFloorY()==55)
humanoid.Health=0;assert(services.GetFloorY()==nil)
''')

class SceneRadiusPolicy(unittest.TestCase):
    def test_masks_override_combat_exemptions_and_preserve_physics(self):
        source=(ROOT/'extras/antilag.luau').read_text()
        game=source[source.index('local function applyGamePolicy('):source.index('local function verticalDecision(')]
        scene=source[source.index('local function applyScenePolicy('):source.index('-- lifecycle')]
        run_lua(game+scene+'''
Enum={HumanoidDisplayDistanceType={None='none'}}
local function object(class,name,parent)
 return {Name=name or class,Parent=parent,CanCollide=true,CanTouch=true,CanQuery=true,
 IsA=function(_,kind) return kind==class end,GetAttribute=function() end}
end
local ball=object('BasePart','GameBall')
local target,watch=applyGamePolicy(ball,{LocalTransparencyModifier=1},false,{GameKeepIndicators=true})
assert(target.LocalTransparencyModifier==nil)
target,watch=applyScenePolicy(ball,target,watch,{}, {[ball]=true},false,nil)
assert(target.LocalTransparencyModifier==1 and watch,'radius did not override ball exemption')
assert(target.CanCollide==nil and target.CanTouch==nil and target.CanQuery==nil and target.Anchored==nil)
for _,class in ipairs({'ParticleEmitter','Trail','Beam','Highlight','Light','BillboardGui','SurfaceGui','Smoke','Fire','Sparkles'}) do
 local o=object(class);local t,w=applyScenePolicy(o,{},false,{}, {[o]=true},false,nil)
 assert(t.Enabled==false and w,class..' was still visible')
 local restored=applyScenePolicy(o,{},false,{}, {},false,nil);assert(next(restored)==nil,class..' mask survived restoration')
end
for _,class in ipairs({'ForceField','Explosion','PVAdornment'}) do
 local o=object(class);assert(applyScenePolicy(o,{},false,{}, {[o]=true},false,nil).Visible==false)
end
local hum=object('Humanoid');assert(applyScenePolicy(hum,{},false,{}, {[hum]=true},false,nil).DisplayDistanceType=='none')
local decal=object('Decal');assert(applyScenePolicy(decal,{},false,{}, {[decal]=true},false,nil).Transparency==1)
''')
