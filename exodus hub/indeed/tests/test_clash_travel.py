"""Incoming TTI is a per-target observation, not an elapsed session timer."""
import unittest
from test_logic_reliability import COMMON, module, run_case

class ClashTravel(unittest.TestCase):
    def test_incoming_samples_survive_waits_restarts_and_death(self):
        run_case(COMMON+'''
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
local player={UserId=42};local root={Parent=true,Position=v()}
local u={now=function() return tm end,getLocalPlayer=function() return player end,getPlayers=function() return {} end}
local g={getClashContext=function() return nil end,getPlayerMotion=function() return v(10) end}
local geometry={getKillRadius=function() return 4 end,getDefensePhysics=function() return {} end}
''' + module('aux/clashstats.luau')+'''
assert(mod.setup({Utils=u,GameInfo=g,DeflectGeometry=geometry}))
local ball={};local session={active=true,partner=99,root=root}
local s={ball=ball,targetId=42,exchangeTargetId=42,position=v(14),velocity=v(-100),speed=100}
mod.begin(99,tm);mod.observe(session,s,tm,true)
assert(math.abs(mod.getStatus().lastIncomingTTI-.1)<1e-9)
tm=tm+100;mod.observe(session,s,tm,true)
assert(mod.getStatus().lastIncomingTTI==.1 and mod.getStatus().travelElapsed==nil)
s.exchangeTargetId=99;mod.observe(session,s,tm,true)
s.exchangeTargetId=42;s.position=v(34);tm=tm+.01;mod.observe(session,s,tm,true)
local r=mod.getStatus();assert(math.abs(r.lastIncomingTTI-.3)<1e-9 and math.abs(r.previousIncomingTTI-.1)<1e-9)
mod.begin(99,tm);mod.observe(session,s,tm,true)
assert(mod.getStatus().previousIncomingTTI==.1,'clash restart erased incoming history')
tm=tm+5;mod.freeze(42,session)
r=mod.getStatus();assert(r.frozen and r.lastIncomingTTI==.3 and r.previousIncomingTTI==.1)
''')

    def test_outgoing_or_unreachable_ball_cannot_make_infinite_tti(self):
        run_case(COMMON+'''
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
local player={UserId=42};local root={Parent=true,Position=v()}
local u={now=function() return tm end,getLocalPlayer=function() return player end,getPlayers=function() return {} end}
local g={getClashContext=function() return nil end,getPlayerMotion=function() return v(10) end}
local geometry={getKillRadius=function() return 4 end,getDefensePhysics=function() return {} end}
'''+module('aux/clashstats.luau')+'''
assert(mod.setup({Utils=u,GameInfo=g,DeflectGeometry=geometry}))
local session={active=true,partner=99,root=root}
local s={ball={},targetId=42,exchangeTargetId=99,position=v(34),velocity=v(-100),speed=100}
mod.observe(session,s,tm,true);assert(mod.getStatus().lastIncomingTTI==nil)
assert(math.abs(mod.getStatus().lastOutgoingTTI-.2)<1e-9,'opponent TTI was not sampled on target change')
s.exchangeTargetId=42;s.velocity=v(100);tm=tm+.01;mod.observe(session,s,tm,true)
assert(mod.getStatus().incomingRecordedAt==tm and mod.getStatus().lastIncomingTTI==nil)
s.velocity=v(-100);tm=tm+10;mod.observe(session,s,tm,false)
assert(mod.getStatus().lastIncomingTTI==nil,'same target was resampled from a frame')
assert(math.abs(mod.getStatus().lastOutgoingTTI-.2)<1e-9,'opponent TTI changed after arrival')
''')
