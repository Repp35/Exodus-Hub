"""Loader failures must never fall back to stale code."""
from pathlib import Path
import unittest
from test_raw_target_parry import run_lua
SOURCE = (Path(__file__).resolve().parents[2] / 'loader.luau').read_text()

class RequestTimeout(unittest.TestCase):
    def test_hung_requests_time_out_and_pending_count_recovers(self):
        source = SOURCE[SOURCE.index('local requestState ='):SOURCE.index('local function request(url, headers)')]
        source = source.replace('requestState.pending += 1', 'requestState.pending = requestState.pending + 1')
        source = source.replace('requestState.pending -= 1', 'requestState.pending = requestState.pending - 1')
        run_lua('''
local CONFIG={MAX_PENDING_REQUESTS=1,REQUEST_TIMEOUT=2}
local now=0; os.clock=function() return now end
local delayed; local task={spawn=function(f) delayed=f end,wait=function() now=now+1 end}
local requestFunction=function() return {StatusCode=200,Body='ok'} end
local function headerValue() end
local function retryAfter() return 0 end
_G.ExodusRequestState=nil
''' + source + '''
local body,err=requestOnce('url',{})
assert(body==nil and err:find('limite') and requestState.pending==1)
body,err=requestOnce('url',{})
assert(body==nil and err:find('pendentes') and requestState.pending==1)
delayed(); assert(requestState.pending==0)
task.spawn=function(f) f() end
assert(requestOnce('url',{})=='ok' and requestState.pending==0)
''')

