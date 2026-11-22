"""Test camera zoom activation, external changes, and cleanup."""
import unittest
from test_raw_target_parry import ROOT, run_lua

class InfiniteZoomTests(unittest.TestCase):
    def test_toggle_reset_and_teardown(self):
        source=(ROOT / 'features/infinitezoom.luau').read_text()
        run_lua('''
local raw=128; local zoomCallback; local connections=0
local player=setmetatable({}, {
  __index=function(_,k)
    if k=='CameraMaxZoomDistance' then return raw end
    if k=='GetPropertyChangedSignal' then return function() return {Connect=function(_,fn)
      zoomCallback=fn; connections=connections+1
      return {Disconnect=function() zoomCallback=nil; connections=connections-1 end}
    end} end end
  end,
  __newindex=function(_,k,v) if k=='CameraMaxZoomDistance' then raw=v; if zoomCallback then zoomCallback() end end end,
})
local cfg={UniversalInfiniteZoom=false}; local observer
local utils={getLocalPlayer=function() return player end,getConfigValue=function(k) return cfg[k] end,recordError=function(_,message) error(message) end}
function utils.observeConfig(fn) observer=fn; return {Disconnect=function() observer=nil end} end
function utils.setConfig(patch)
  local changed={}; for k,v in pairs(patch) do if cfg[k]~=v then cfg[k]=v; changed[k]=v end end
  if next(changed) and observer then observer(changed) end; return true
end
local module=(function()\n''' + source + '''\nend)()
assert(module.setup({Utils=utils})); assert(raw==128 and connections==0)
assert(module.setEnabled(true)); assert(raw==1000000 and cfg.UniversalInfiniteZoom and connections==1)
player.CameraMaxZoomDistance=50; assert(raw==1000000,'game changed limit while enabled')
assert(module.setEnabled(false)); assert(raw==128 and not cfg.UniversalInfiniteZoom and connections==0)
utils.setConfig({UniversalInfiniteZoom=true}); assert(raw==1000000 and connections==1)
utils.setConfig({UniversalInfiniteZoom=false}); assert(raw==128 and connections==0)
assert(module.setEnabled(true)); assert(module.teardown()); assert(raw==128 and connections==0 and observer==nil)
''')

if __name__ == '__main__': unittest.main()
