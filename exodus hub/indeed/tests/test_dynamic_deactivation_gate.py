"""Auto Spam and Dynamic share the same deactivation conditions."""
import unittest
from autospam_harness import check

class SharedDeactivationGate(unittest.TestCase):
    def test_both_stop_for_ball_leaving_exchange(self):
        check('''
packet(42,0,2)
local session=ap.createManualSession(); assert(session)
snap.position=v(300);snap.velocity=v(600)
assert(ap.getManualStopReason(session,0)==nil)
assert(ap.canSend())
advance(.13);snap.syncAt=tm
local reason=ap.getManualStopReason(session,0)
assert(reason=='ball_left_exchange',tostring(reason))
assert(not ap.canSend())
stopped(reason)
''')

    def test_auto_spam_stops_without_dynamic_initial_protection(self):
        check('''
packet(42,0,2)
local session=ap.createManualSession(); assert(session)
snap.position=v(300);snap.velocity=v(600)
local protectedUntil=tm+.3
assert(ap.getManualStopReason(session,protectedUntil)==nil)
assert(ap.canSend())
advance(.13);snap.syncAt=tm
assert(ap.getManualStopReason(session,protectedUntil)==nil,'Dynamic protection changed')
assert(not ap.canSend(),'Auto Spam incorrectly acquired a protection delay')
stopped('ball_left_exchange')
''')
