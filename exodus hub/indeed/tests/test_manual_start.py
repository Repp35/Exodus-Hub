"""Manual activation must not inherit an unrelated opponent or old idle time."""
import unittest
from test_raw_target_parry import ROOT, run_lua

class ManualStart(unittest.TestCase):
    def test_start_far_then_engage_then_escape(self):
        source=(ROOT/'autospam.luau').read_text()
        code=source[source.index('function AutoSpam.canSendManual()'):source.index('function AutoSpam.canSend()')]
        run_lua('''
local V={}; V.__index=function(t,k) if k=='Magnitude' then return math.abs(t.x) end return V[k] end
V.__sub=function(a,b) return setmetatable({x=a.x-b.x},V) end
local function v(x) return setmetatable({x=x},V) end
local function typeof(x) return getmetatable(x)==V and 'Vector3' or type(x) end
local time=10; local on=true; local target=99; local distance=100
local current={root={Parent=true,Position=v(0)},character={Parent=true},stationary=true,previousOpponent=88}
local utils={isManualSpamActive=function() return on end,isActive=function() return true end,setManualSpamActive=function(x) on=x end,recordTransition=function() end}
local gameInfo={getSnapshotAt=function() return {targetId=target} end,getPlayerMotion=function() return v(distance) end}
local localPlayer={UserId=42}; local CONFIG={DEACTIVATION={STATIONARY_TIMEOUT=.3,MANUAL_COOLDOWN_TIMEOUT=.2}}
local function freshSnapshot() return true end
local function now() return time end
local function userId(x) return x end
local function playerIsAlive() return true end
local function distanceLimit() return 20 end
local function dashEscapeRisk() return nil end
local function cooldownExpired() return false end
local cd={blocking=false}; local cooldownInfo={getDeflectCooldownState=function() return cd end}
local function finite(x) return type(x)=="number" and x==x and math.abs(x)<math.huge end
local AutoSpam={}
''' + code + '''
assert(AutoSpam.canSendManual() and on,'first click cancelled by distant target or old stationary state')
time=20; assert(AutoSpam.canSendManual() and on,'unrelated distant target cancelled manual')
distance=10; assert(AutoSpam.canSendManual() and on)
time=20.1; assert(AutoSpam.canSendManual() and on,'stationary timer inherited from before activation')
current.stationary=false; distance=30; assert(AutoSpam.canSendManual() and on,'distant opponent disabled manual')
on=true; current.manual=nil; current.stationary=true; distance=100; time=30
cd.blocking=true; cd.blockingSince=30
assert(AutoSpam.canSendManual() and on)
time=30.199; assert(AutoSpam.canSendManual() and on,'cooldown stopped before 200ms')
time=30.201; assert(AutoSpam.canSendManual() and on,'cooldown disabled manual spam')
time=100; assert(AutoSpam.canSendManual() and on,'long cooldown disabled manual spam')
cd.miss=true; assert(not AutoSpam.canSendManual() and not on,'miss did not disable manual spam')
cd.miss=false; on=true; assert(AutoSpam.canSendManual() and on,'manual did not recover after miss cleared')
''')

if __name__ == '__main__': unittest.main()
