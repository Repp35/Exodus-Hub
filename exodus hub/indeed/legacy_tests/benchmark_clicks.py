"""Offline scheduler/dispatch comparison; not a Roblox or network benchmark."""
import sys,re,subprocess
from pathlib import Path
REPO = Path(__file__).resolve().parents[3]
MODULES = REPO / 'exodus hub/modules'
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_logic_reliability import COMMON,SPAM
from test_raw_target_parry import run_lua

def translate(source):
 return re.sub(r'([A-Za-z_][\w.]*) ([+\-*/%])= ([^;\n]+?)(?=;|\n| end| else\b)',lambda m:f'{m[1]} = {m[1]} {m[2]} ({m[3]})',source)
BASELINE = '2b9184909f6490e1f41fceec78d7787733a88dce'
def previous(path):
 path={'combat/spam.luau':'spam.luau','combat/remote.luau':'aux/remote.luau'}[path]
 return subprocess.check_output(['git','show',f'{BASELINE}:exodus hub/modules/logic/{path}'],cwd=REPO).decode()
def main():
 for label,sp,rp in [('before',previous('combat/spam.luau'),previous('combat/remote.luau')),('after',(MODULES/'combat/spam.luau').read_text(),(MODULES/'combat/remote.luau').read_text())]:
  script='local cpuClock=os.clock\n'+COMMON+SPAM+'''
 local checks=0;a.canSendManual=function() checks=checks+1;return manual end
 local storage={FindFirstChild=function() return nil end}
 game={GetService=function() return storage end}
 local ability={LastDeflectCallAt=0,Deflect=function(self) count=count+1;self.LastDeflectCallAt=count end}
 g.isTrainingArea=function() return false end;g.getDeflectAbility=function() return ability end
 '''+ 'r=(function()\n'+translate(rp)+'\nend)()\nassert(r.setup({GameInfo=g,Utils=u}))\nlocal mod=(function()\n'+translate(sp)+'''\nend)()
 mode='CPF';rate=100
 assert(mod.setup({Utils=u,Remote=r,GameInfo=g,AutoSpam=a}))
 collectgarbage('collect');collectgarbage('stop');local mem=collectgarbage('count');local start=cpuClock()
 for i=1,1200 do frame(1/60) end
 local elapsed=cpuClock()-start;local growth=collectgarbage('count')-mem
 assert(count==120000)
 '''+ f'''print('{label}', 'clicks',count,'checks',checks,'cpu_seconds',string.format('%.4f',elapsed),'allocated_KiB',string.format('%.1f',growth))\n'''
  run_lua(script)

if __name__ == "__main__":
 main()
