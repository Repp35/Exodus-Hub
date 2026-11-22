"""Personal round membership is independent of the global active-round flag."""
import unittest
from test_logic_reliability import COMMON, GAME_INFO, module, run_case

class GameMembership(unittest.TestCase):
    def check(self, script, initial=''):
        run_case(COMMON+GAME_INFO+'''
game={PlaceId=12979690461}
local attrs={MatchStatus=6,CurGamemode=0};local pa={Lives=1,Playing=true}
world.GetAttribute=function(_,key) return attrs[key] end
player.GetAttribute=function(_,key) return pa[key] end
local hum={Health=100,Died=signal()}
character.FindFirstChildOfClass=function() return hum end
local heart=signal();u.getRunService=function() return {Heartbeat=heart} end
u.trackGlobal=function() end;u.untrackGlobal=function() end
local lobby=instance('BasePart');lobby.Size=v(30,30,30)
lobby.CFrame={PointToObjectSpace=function(_,point) return point-v(-1000,0,0) end}
world.children['Lobby Area']=lobby
'''+initial+module('game/gameinfo.luau')+'''
assert(mod.setup({Utils=u}))
local function tick() heart:Fire(.1) end
'''+script)

    def test_death_blocks_reentry_until_round_end_and_fresh_teleport(self):
        self.check('''
assert(mod.getGameContext().inMatch)
hum.Health=0;hum.Died:Fire();assert(not mod.getGameContext().inMatch)
hum.Health=100;player.Character=instance('Model',{HumanoidRootPart=root})
player.Character.FindFirstChildOfClass=function() return hum end
root.Position=v(200);tick()
assert(not mod.getGameContext().inMatch,'respawn/stale lives rejoined the active round')
attrs.MatchStatus=1;tick();attrs.MatchStatus=6;tick()
assert(not mod.getGameContext().inMatch,'new round without teleport counted as participation')
root.Position=v(400);tick();assert(mod.getGameContext().inMatch)
''')

    def test_active_global_round_and_stale_lives_in_lobby_do_not_mean_participation(self):
        self.check('''
assert(mod.getGameContext().roundActive and not mod.getGameContext().inMatch)
pa.Lives=3;pa.Playing=true;tick()
assert(not mod.getGameContext().inMatch,'lobby with stale positive lives counted as a match')
attrs.MatchStatus=1;tick();attrs.MatchStatus=6;tick()
root.Position=v(0);tick();assert(mod.getGameContext().inMatch)
''', 'root.Position=v(-1000);pa.Lives=0;pa.Playing=false\n')
