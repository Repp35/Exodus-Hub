"""One bounded early burst at extreme contact, confirmed only by a real exchange."""
import unittest
from autospam_harness import check as run_check

def check(case):
    run_check("g.getDeflectTargetPrediction=function() return 42 end\n"+case)

class ExtremeContact(unittest.TestCase):
    def test_starts_before_local_target_and_continues_after_exchange(self):
        check('''
other.root.Position=v(4.4);snap.syncSpeed=83;snap.speed=83;snap.velocity=v(-83)
packet(99,0,15);assert(ap.isActive() and clicks>0,'did not pre-arm before target receipt')
assert(ap.getActivationContext().reason=='extreme_return_prediction')
packet(42,.05,5);heartbeat(.3);assert(ap.isActive(),'confirmed exchange did not preserve spam')
''')

    def test_unconfirmed_attempt_expires_and_cannot_loop_on_same_leg(self):
        check('''
other.root.Position=v(4);packet(99,0,12);assert(ap.isActive())
heartbeat(.241);stopped('anticipation_expired')
for i=1,10 do packet(99,.02,12) end
assert(not ap.isActive(),'unconfirmed leg retriggered speculative burst')
''')

    def test_redirection_preserves_immediate_stop(self):
        check('''
other.root.Position=v(4);packet(99,0,12);assert(ap.isActive())
packet(88,.01,12);assert(not ap.isActive(),'third target did not cancel anticipation')
''')

    def test_distance_and_arrival_gates_keep_normal_gameplay(self):
        for setup in ('other.root.Position=v(300);packet(99,0,310)',
                      'other.root.Position=v(4);packet(99,0,300)',
                      'other.root.Position=v(4);snap.velocity=v(600);packet(99,0,50)',
                      'other.root.Position=v(4);snap.locked=true;packet(99,0,12)'):
            with self.subTest(setup=setup):
                check(setup+';assert(not ap.isActive())')

    def test_dynamic_radius_changes_with_speed_at_same_distance(self):
        for speed in (16,600):
            with self.subTest(speed=speed):
                check(f'''
other.root.Position=v(20);snap.syncSpeed={speed};snap.speed={speed};snap.velocity=v(-{speed})
packet(99,0,30)
assert(ap.isActive()==({speed}==600),'anticipation still used fixed studs')
''')

    def test_wrong_facing_or_ambiguous_selection_blocks_and_cancels(self):
        for target in ('99','nil'):
            with self.subTest(target=target):
                check(f'''
g.getDeflectTargetPrediction=function() return {target} end
other.root.Position=v(4);packet(99,0,12);assert(not ap.isActive())
''')
        check('''
other.root.Position=v(4);packet(99,0,12);assert(ap.isActive())
g.getDeflectTargetPrediction=function() return 88 end
ap.canSend();assert(not ap.isActive(),'aim changed but speculative burst continued')
''')

class NativeSelection(unittest.TestCase):
    def test_camera_alignment_and_competing_targets(self):
        from test_logic_reliability import COMMON, ROOT, run_case
        source=(ROOT/'aux/gameinfo.luau').read_text()
        code=source[source.index('function GameInfo.getDeflectTargetPrediction('):source.index('function GameInfo.getPlayerDistance(')]
        run_case(COMMON+'''
local oldIndex=V.__index
V.__index=function(t,k) if k=='Unit' then return t/t.Magnitude end return oldIndex(t,k) end
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
local function finiteVector(x) return typeof(x)=='Vector3' end
local function person(id,pos)
 local root={Parent=true,Position=pos,CFrame={cf=true,Position=pos,LookVector=v(1)}}
 local char={FindFirstChild=function() return root end,FindFirstChildOfClass=function() return {Health=100} end}
 local p={UserId=id,Character=char,attrs={},root=root}
 function p:GetAttribute(key) return self.attrs[key] end
 return p
end
local source,me,third=person(99,v()),person(42,v(20)),person(88,v(0,20))
local originalTypeof=typeof;typeof=function(x) if type(x)=='table' and x.cf then return 'CFrame' end return originalTypeof(x) end
source.attrs.CamCFrame=source.root.CFrame
local list={source,me,third}
local players={GetPlayers=function() return list end,GetPlayerByUserId=function(_,id) for _,p in ipairs(list) do if p.UserId==id then return p end end end}
local mode=0;local world={GetAttribute=function() return mode end}
local function playerRoot(id) local p=players:GetPlayerByUserId(id);return p and p.root,p and p.Character end
local GameInfo={}
'''+code+'''
assert(GameInfo.getDeflectTargetPrediction(99)==42)
source.attrs.CamCFrame.LookVector=v(0,1);assert(GameInfo.getDeflectTargetPrediction(99)==88)
source.attrs.CamCFrame.LookVector=v(1);third.root.Position=v(20,.1)
assert(GameInfo.getDeflectTargetPrediction(99)==nil,'ambiguous alignment was claimed as certain')
third.attrs.IsCloaked=true;assert(GameInfo.getDeflectTargetPrediction(99)==42)
mode=1;source.attrs.PlayerTeam='red';me.attrs.PlayerTeam='red'
assert(GameInfo.getDeflectTargetPrediction(99)==nil,'teammate was selected')
mode=0;third.attrs.IsCloaked=false;third.attrs.DarkSealed=true
assert(GameInfo.getDeflectTargetPrediction(99)==88)
''')
