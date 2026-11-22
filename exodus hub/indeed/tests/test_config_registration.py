"""The UI registers without exposing AutoSpam tuning settings."""
import unittest
from test_ui_library import PRELUDE, MOCK, module
from test_raw_target_parry import run_lua

class ConfigRegistration(unittest.TestCase):
    def test_ui_schema_registers_without_autospam_tuning(self):
        run_lua(PRELUDE + MOCK + module('config') + module('uiconfig') + """
assert(config.register('uiconfig',uiconfig.__config),'UI schema rejected')
assert(config.defaults().AutoSpam==true)
assert(config.validatePatch({AutoSpam=false}))
for _,key in ipairs({'ClashGrace','ClashMaxDistance','ClashMaxAge','AutoSpamClashPrediction','AutoSpamPredictionMargin'}) do
 assert(config.defaults()[key]==nil)
 assert(uiconfig.__config.schema[key]==nil)
 assert(not config.validatePatch({[key]=1}))
end
""")
