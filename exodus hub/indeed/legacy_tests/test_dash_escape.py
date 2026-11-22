"""Manual dispatch remains independent of dash evidence."""
import unittest
from autospam_harness import check

class DashEscapeTests(unittest.TestCase):


    def test_dash_evidence_does_not_disable_manual(self):
        check('''
u.setManualSpamActive(true);cd.blocking=true;cd.blockingSince=tm;dash(99,120)
packet(99,.06,50);assert(ap.canSendManual() and manual)
''')

if __name__=='__main__': unittest.main()
