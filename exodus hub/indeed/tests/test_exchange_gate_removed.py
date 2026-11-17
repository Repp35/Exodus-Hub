"""Removed danger estimates cannot activate spam; original candidates still can."""
import unittest
from autospam_harness import check

class RemovedExchangeGate(unittest.TestCase):
    def test_fast_far_cycles_and_late_ap_cannot_activate_removed_gate(self):
        check('''other.root.Position=v(80)
defender.getPressureDetector=function() error('AutoSpam must not read the removed detector') end
defense.lastAcceptedSample={at=tm,ball=ball,distance=4,speed=600}
packet(99,0,100)
for i=1,20 do packet(i%2==1 and 42 or 99,.04,100) end
assert(not ap.isActive() and clicks==0,'removed gate still activated')
assert(ap.getStatus().risk==nil)''')

    def test_near_spawn_has_only_original_proximity_rules(self):
        check('''other.root.Position=v(13);packet(42,0,5)
for i=1,10 do heartbeat(.01) end
assert(not ap.isActive() and clicks==0)''')

    def test_original_instant_close_candidate_still_activates(self):
        check('''packet(42,0,2)
assert(ap.isActive() and ap.getActivationContext().reason=='close_target')''')

    def test_original_return_candidate_still_activates(self):
        check('''packet(42,0,50);packet(99,.04,50);packet(42,.04,50)
assert(ap.isActive() and ap.getActivationContext().reason=='return_target')''')

if __name__=='__main__':unittest.main()
