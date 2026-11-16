"""Dash escape uses 50 ms and has no proximity protection."""
import unittest
from autospam_harness import check

class DashEscapeTests(unittest.TestCase):
    def test_close_dash_escape_stops_at_50ms(self):
        for id,velocity in ((99,120),(42,-120)):
            with self.subTest(id=id):
                check(f'''
packet(42,0,2);snap.syncSpeed=16;snap.speed=16;snap.velocity=v(-16)
packet(99,.01,50);cd.blocking=true;cd.blockingSince=tm;dash({id},{velocity})
heartbeat(.049);assert(ap.isActive());heartbeat(.002)
stopped({'"opponent_dash_escape"' if id==99 else '"self_dash_escape"'})
''')

    def test_no_cooldown_vertical_dash_or_ball_still_near_does_not_escape(self):
        for mutation in ("cd.blocking=false","dashSamples[99].velocity=v(0,120)","snap.position=v(8)"):
            with self.subTest(mutation=mutation):
                check('''
packet(42,0,2);snap.syncSpeed=16;snap.speed=16;snap.velocity=v(-16)
packet(99,.01,50);cd.blocking=true;cd.blockingSince=tm;dash(99,120)
'''+mutation+";heartbeat(.06);assert(ap.isActive())")

    def test_escape_does_not_disable_manual(self):
        check('''
u.setManualSpamActive(true);cd.blocking=true;cd.blockingSince=tm;dash(99,120)
packet(99,.06,50);assert(ap.canSendManual() and manual)
''')

if __name__=='__main__': unittest.main()
