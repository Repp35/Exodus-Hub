"""Independent votes from the targeting paths verified in the game dump."""
import unittest
from test_logic_reliability import COMMON, module, run_case

FIXTURE = '''
task={defer=function(fn) fn() end}
local originalTypeof=typeof
function typeof(value) return type(value)=='table' and value._type or originalTypeof(value) end
Color3={fromRGB=function(r,g,b) return {_type='Color3',R=r/255,G=g/255,B=b/255} end}
local red=Color3.fromRGB(202,56,30);local gray=Color3.fromRGB(153,153,153)
local white=Color3.fromRGB(255,255,255);local arrowRed=Color3.fromRGB(255,0,0)
local function sequence(color) return {_type='ColorSequence',Keypoints={{Time=0,Value=color},{Time=1,Value=color}}} end
local function object(class,name,parent)
 local o={_type='Instance',ClassName=class,Name=name,Parent=parent,children={},attrs={},Enabled=true,Visible=true,Transparency=0,LocalTransparencyModifier=0}
 function o:IsA(kind) return kind==class or (class=='ImageLabel' and kind=='GuiObject') end
 function o:IsDescendantOf(root) local p=self.Parent while p do if p==root then return true end;p=p.Parent end return false end
 function o:FindFirstChild(n) return self.children[n] end
 function o:FindFirstChildOfClass(kind) for _,c in pairs(self.children) do if c:IsA(kind) then return c end end end
 function o:GetAttribute(key) return self.attrs[key] end
 if parent then parent.children[name]=o end
 return o
end
local world=object('Workspace','Workspace');world.attrs.MatchStatus=6;world.attrs.GameBallTarget=99
local storage=object('ReplicatedStorage','ReplicatedStorage')
local inventory=object('Folder','Inventory',storage);local skins=object('Folder','BallSkins',inventory)
local skinModule=object('ModuleScript','Verity',skins);skinModule.data={Faces={serious_1='serious',evil='evil',crazy='crazy',crazy_talking='crazy_talk',neutral='neutral',hurt='hurt'}}
require=function(m) return m.data end
local me=object('Player','me');me.UserId=42;me.Character=object('Model','meCharacter',world)
local other=object('Player','other');other.UserId=99;other.Character=object('Model','otherCharacter',world)
local players={GetPlayers=function() return {other,me} end}
local highlight=object('Highlight','PlayerBallHighlight',other.Character)
local ball=object('BasePart','GameBall',world);ball.Color=gray
local trails=object('Folder','Trails',ball)
local normal=object('Trail','BallTrail2',trails);normal.Color=sequence(white)
local target=object('Trail','BallTrailTarget',trails);target.Color=sequence(red)
local trail=object('Trail','BallTrail',trails);trail.Color=normal.Color
local face=object('BasePart','SkinFace',ball);local decal=object('Decal','Decal',face);decal.Transparency=1;decal.Texture='neutral'
local gui=object('PlayerGui','PlayerGui',me);local interface=object('ScreenGui','Interface',gui)
local ballUI=object('Frame','BallIndicatorUI',interface);local indicator=object('ImageLabel','Indicator',ballUI);indicator.ImageColor3=white
local latest={seq=10,serverTime=100,targetId=99,highlightId=99}
local provider={hasState=true,lastSeq=10,syncData={TargetPlayerID=99,HighlightTargetPlayerID=99},latestTargetId=99,history={latest},IsLocalTarget=function() return false end}
local context={player=me,players=players,world=world,ball=ball,sync={TargetPlayerID=99,HighlightTargetPlayerID=99},syncFresh=true,provider=provider,serverNow=100,maxAge=.5,sequence=10,active=true}
'''

def check(case):
    run_case(COMMON+FIXTURE+module('aux/targeting.luau')+'''
local resolver=mod.create({storage=function() return storage end})
local function signal(report,name) for _,s in ipairs(report.signals) do if s.name==name then return s end end error(name) end
'''+case)

class TargetingVotes(unittest.TestCase):
    def test_each_verified_source_can_authorize_despite_other_negative_votes(self):
        cases={
            'sync.target':'context.sync.TargetPlayerID=42',
            'sync.highlight':'context.sync.HighlightTargetPlayerID=42',
            'replicator.target':'provider.syncData.TargetPlayerID=42',
            'replicator.highlight':'provider.syncData.HighlightTargetPlayerID=42',
            'replicator.latestTargetId':'provider.latestTargetId=42',
            'replicator.IsLocalTarget':'provider.IsLocalTarget=function() return true end',
            'history.target':'latest.targetId=42',
            'history.highlight':'latest.highlightId=42',
            'workspace.GameBallTarget':'world.attrs.GameBallTarget=42',
            'character.PlayerBallHighlight':"other.Character.children.PlayerBallHighlight=nil;highlight.Parent=me.Character;me.Character.children.PlayerBallHighlight=highlight",
            'ball.color':'ball.Color=red',
            'ball.trail':'trail.Color=target.Color',
            'ui.BallIndicator':'indicator.ImageColor3=arrowRed',
            'ball.skinFace':"ball.attrs.BallSkin='Verity';decal.Transparency=0;decal.Texture='serious'",
        }
        for name,mutation in cases.items():
            with self.subTest(source=name):
                check(mutation+f'''
local report=resolver.resolve(context)
assert(report.targeted and report.targetId==42 and report.conflict,'positive vote was vetoed')
assert(#report.signals==14 and #report.positive==1)
assert(signal(report,'{name}').state=='yes')
''')

    def test_expired_and_out_of_order_network_state_cannot_vote_positive(self):
        check('''
context.sync.TargetPlayerID=42;provider.latestTargetId=42;provider.syncData.TargetPlayerID=42;latest.targetId=42
context.syncFresh=false;context.serverNow=101
local r=resolver.resolve(context);assert(not r.targeted)
assert(not signal(r,'sync.target').available and not signal(r,'history.target').available)
context.syncFresh=true;context.sync.TargetPlayerID=99;context.serverNow=100;context.sequence=11
r=resolver.resolve(context);assert(not r.targeted,'older provider overrode accepted packet')
assert(not signal(r,'replicator.target').available)
''')

    def test_visual_ambiguity_and_disabled_elements_are_unavailable(self):
        check('''
ball.Color=red;ball.attrs.SkinNormalColor=red
trail.Color=target.Color;normal.Color=target.Color
indicator.ImageColor3=arrowRed;interface.Enabled=false
highlight.Enabled=false
local r=resolver.resolve(context);assert(not r.targeted)
assert(signal(r,'ball.color').reason=='ambiguous_skin_color')
assert(signal(r,'ball.trail').reason=='ambiguous_trail')
assert(signal(r,'ui.BallIndicator').reason=='indicator_hidden')
ball.attrs.SkinNormalColor=nil;ball.LocalTransparencyModifier=1
r=resolver.resolve(context);assert(not r.targeted and signal(r,'ball.color').reason=='ball_hidden')
''')

    def test_transient_faces_and_non_target_colors_never_claim_target(self):
        check('''
ball.attrs.BallSkin='Verity';decal.Transparency=0;decal.Texture='hurt'
ball.Color=Color3.fromRGB(70,255,120)
local r=resolver.resolve(context);assert(not r.targeted and not signal(r,'ball.skinFace').available)
assert(not signal(r,'ball.color').available,'possession was treated as a target decision')
decal.Texture='serious';skinModule.data.Faces.neutral='serious'
r=resolver.resolve(context);assert(not r.targeted,'shared expression texture falsely confirmed target')
''')

    def test_failures_are_isolated_and_inactive_round_clears_all_votes(self):
        check('''
provider.IsLocalTarget=function() error('unavailable') end
world.attrs.GameBallTarget=42
local r=resolver.resolve(context);assert(r.targeted and signal(r,'replicator.IsLocalTarget').reason=='read_failed')
context.active=false;r=resolver.resolve(context)
assert(not r.targeted and not r.known)
for _,s in ipairs(r.signals) do assert(s.state=='unavailable' and s.reason=='round_inactive') end
''')

class TargetingExchangeIntegration(unittest.TestCase):
    def test_visual_positive_does_not_fabricate_dash_exchange_or_close_receipt(self):
        from autospam_harness import check as check_spam
        check_spam('''
snap.targetSignals={targeted=true};snap.targetId=42;snap.exchangeTargetId=99;snap.position=v(5)
dash(99,-120)
ap.onBallSync({Source='packet',Sequence=2,TargetPlayerID=99})
assert(not ap.isActive(),'visual positive invented an incoming receipt or dash exchange')
snap.targetId=42;snap.exchangeTargetId=42;snap.syncSequence=3
ap.onBallSync({Source='packet',Sequence=3,TargetPlayerID=42})
assert(ap.isActive(),'actual incoming receipt was not recognized')
''')
