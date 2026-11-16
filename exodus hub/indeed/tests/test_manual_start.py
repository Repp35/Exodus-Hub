"""Manual mode remains independent of automatic activation evidence."""
import unittest
from autospam_harness import check

class ManualStart(unittest.TestCase):
    def test_only_miss_disables_manual(self):
        check('''
cfg.AutoSpam=false;other.root.Position=v(100);u.setManualSpamActive(true)
cd.blocking=true;cd.blockingSince=tm
packet(99);heartbeat(2);assert(manual and ap.canSendManual() and clicks>0)
cd.miss=true;heartbeat(.01);assert(not manual and not ap.canSendManual())
cd.miss=false;u.setManualSpamActive(true);assert(ap.canSendManual())
''')

if __name__=='__main__': unittest.main()
