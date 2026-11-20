"""The actual UI configuration must register before the loader can start."""
import unittest
from test_ui_library import PRELUDE, MOCK, module
from test_raw_target_parry import run_lua

class ConfigRegistration(unittest.TestCase):
    def test_ui_schema_registers_and_prediction_margin_is_bounded(self):
        run_lua(PRELUDE + MOCK + module('config') + module('uiconfig') + '''
assert(config.register('uiconfig',uiconfig.__config),'UI schema rejected')
assert(config.defaults().AutoSpamPredictionMargin==1)
for _,value in ipairs({0.5,1,2}) do assert(config.validatePatch({AutoSpamPredictionMargin=value})) end
for _,value in ipairs({0.49,2.01,-1}) do assert(not config.validatePatch({AutoSpamPredictionMargin=value})) end
''')
