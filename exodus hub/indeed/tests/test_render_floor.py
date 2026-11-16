"""Validate the explicit render floor and conservative map visibility."""
import unittest
from test_raw_target_parry import ROOT, run_lua

class RenderFloor(unittest.TestCase):
    def test_only_parts_entirely_below_floor_are_hidden(self):
        source=(ROOT/'extras/antilag.luau').read_text()
        code=source[source.index('local function verticalDecision('):source.index('local function createSpatialController(')]
        code=code.replace('(if previous == "above" then margin else 0)', '(previous == "above" and margin or 0)').replace('(if previous == "below" then margin else 0)', '(previous == "below" and margin or 0)')
        run_lua(code+'''
local options={CullVertical=false,CullFloorY=95}
assert(verticalDecision(80,94,150,nil,options)=='floor')
assert(verticalDecision(90,96,150,nil,options)==nil,'floor hid intersecting geometry')
assert(verticalDecision(95,96,150,nil,options)==nil)
options.CullFloorY=nil; assert(verticalDecision(-100,0,150,nil,options)==nil)
''')

if __name__ == '__main__': unittest.main()
