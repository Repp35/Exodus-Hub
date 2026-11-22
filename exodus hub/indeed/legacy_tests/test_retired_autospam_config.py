import unittest
from test_raw_target_parry import ROOT, run_lua

class RetiredAutoSpamConfig(unittest.TestCase):
 def test_old_tuning_is_removed_silently_and_valid_values_survive(self):
  source = (ROOT / 'core/utils.luau').read_text()
  migration = source[source.index('local function migrateConfig(data)'):source.index('local function readSavedConfig(path)')]
  run_lua('''
local warnings={}
local function warn(message) warnings[#warnings+1]=message end
local function decodeKeyCode(value) return value end
local function isPersistentConfigKey() return true end
local configModule={validatePatch=function(patch)
 for key in pairs(patch) do
  if key~='AutoSpam' and key~='CPS' and key~='AutoParryFactor08Applied' and key~='AutoParryFactor03Applied' then return false,'unknown '..key end
 end
 return true
end}
''' + migration + '''
local data={AutoSpam=false,CPS=123,AutoParryFactor08Applied=true,AutoParryFactor03Applied=true,
 ClashMaxDistance=25,AutoSpamClashPrediction=false,AutoSpamPredictionMargin=1,ClashGrace=.35,ClashMaxAge=.8}
local patch,migrated=migrateConfig(data)
assert(migrated and #warnings==0)
assert(patch.AutoSpam==false and patch.CPS==123)
for _,key in ipairs({'ClashMaxDistance','AutoSpamClashPrediction','AutoSpamPredictionMargin','ClashGrace','ClashMaxAge'}) do assert(patch[key]==nil and data[key]==nil) end
local _,again=migrateConfig(data);assert(not again)
data.UnrelatedUnknown=true;migrateConfig(data);assert(#warnings==1)
''')
