"""Exercise real Spam/Remote through the same permission views as the loader."""
import unittest
from test_logic_reliability import COMMON, SPAM, module, run_case
from test_parry_dispatch import PRELUDE

class SpamPermissions(unittest.TestCase):
    def check(self,case):
        # Engine doubles; permission validation/resolution and both consumers are real.
        run_case(COMMON+SPAM+'local schedulerTask, schedulerClock=task,os.clock\n'+PRELUDE+'''
schedulerTask.delay=task.delay;schedulerTask.defer=task.defer;task=schedulerTask;os.clock=schedulerClock
table.freeze=function(t) return t end
local ability={LastDeflectCallAt=0,Deflect=function(self) count=count+1;self.LastDeflectCallAt=count end}
g.isTrainingArea=function() return false end
g.fireTrainingParry=function() count=count+1;return true end
g.getDeflectAbility=function() return ability end
g.getDarkSealAbility=function() end;g.getFierceDeflectAbility=function() end;g.getDashAbility=function() end
local readConfig=u.getConfigValue
u.getConfigValue=function(key) if key=='ClickMethod' then return method end return readConfig(key) end
local function declare(provider)
 local names={};for name,value in pairs(provider) do if type(value)=='function' then names[#names+1]=name end end
 provider.__contract={provides=names,requires={}}
end
declare(u);declare(g);declare(a)
''' + module('core/permissions.luau').replace('local mod=', 'local permissions=',1)
+ module('combat/remote.luau').replace('local mod=', 'local realRemote=',1)
+ module('combat/spam.luau').replace('local mod=', 'local realSpam=',1)+'''
local loaded={spam=realSpam,remote=realRemote,utils=u,gameinfo=g,autospam=a}
for name,provider in pairs(loaded) do assert(permissions.validate(name,provider)) end
assert(realRemote.setup(permissions.resolve('remote',loaded)))
local deps=permissions.resolve('spam',loaded)
''' + case)

    def test_prepared_dispatch_runs_through_permissions_in_default_and_direct(self):
        self.check('''
method='Deflect';mode='CPF';rate=10
assert(realSpam.setup(deps));frame(1/60)
assert(count==10,'permission-wrapped prepared Deflect did not run')
method='Direct';frame(1/60)
assert(sends==20 and #delayed==10,'prepared Direct dispatch was blocked')
for _,fn in ipairs(delayed) do fn() end
assert(sends==30,'retransmissions lost after wrapping')
manual=false;frame(.02);assert(realSpam.getStatus().phase=='stopped')
''')

    def test_fix_grants_only_prepared_parry_and_keeps_other_methods_denied(self):
        self.check('''
assert(type(deps.Remote.prepareParry)=='function')
local ok,err=pcall(function() return deps.Remote.fireDash end)
assert(not ok and tostring(err):find('Permissão negada'),'permissions were opened to unrelated APIs')
''')

if __name__=='__main__':unittest.main()
