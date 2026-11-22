"""Packet state belongs to each GameInfo session, with no shared mutable cache."""
import unittest
from test_logic_reliability import module, run_case

class BallSyncState(unittest.TestCase):
    def test_sequence_wrap_duplicates_expiration_and_session_isolation(self):
        run_case('''
local now=10; os.clock=function() return now end
table.clone=function(t) local out={} for k,v in pairs(t) do out[k]=v end return out end
local typeof=type
''' + module('game/ballsync.luau') + '''
local invalidated=0; local provider=nil
local function make() return mod.create({packetAge=.5,getReplicator=function() return provider end,
 invalidateSnapshotCache=function() invalidated=invalidated+1 end}) end
local a,b=make(),make()
assert(a.applyPacket({Sequence=65535,Speed=100}))
assert(a.applyPacket({Sequence=0,Speed=110}))
assert(not a.applyPacket({Sequence=0,Speed=999}))
assert(not a.applyPacket({Sequence=65535,Speed=999}))
assert(a.getData().Speed==110 and b.getData()==nil and b.getReceivedAt()==0)
assert(invalidated==2 and a.getSequence(a.getData())==0)
now=11; provider={hasState=true,lastSeq=1,syncData={Sequence=1,Speed=120}}
assert(a.getData().Speed==120)
assert(a.applySync({Sequence=2,Speed=130}).Speed==130)
assert(a.getData().Speed==130 and invalidated==3)
assert(a.applySync({Sequence=1,Speed=150})==nil)
''')

if __name__ == '__main__':
    unittest.main()
