"""Fierce behavior through shared production cooldown, timing and transport."""
import unittest
from test_defenseengine import STACK
from test_logic_reliability import run_case

class AutoFierceTests(unittest.TestCase):
    def check(self, case):
        run_case(STACK + '''
startFierce()
ability.Cooldown=1
packetTo(42)
''' + case)

    def test_current_miss_activates_immediately_once(self):
        self.check('af.onBallSync();assert(fierceCalls==1);af.onBallSync();assert(fierceCalls==1)')
    def test_current_target_and_window_are_required(self):
        for change in ('packetTo(99)', 'packetTo(42,1000)', 'hum.Health=0', 'cfg.AutoFierce=false', 'fierce.Cooldown=1'):
            with self.subTest(change=change):
                self.check(change+';af.onBallSync();assert(fierceCalls==0)')
    def test_current_cooldown_must_still_be_active(self):
        self.check('ability.Cooldown=0;af.onBallSync();assert(fierceCalls==0)')
    def test_unavailable_ability_cannot_rescue(self):
        self.check('fierce.IsAvailable=function() return false end;af.onBallSync();assert(fierceCalls==0)')
    def test_current_target_rechecked_before_send(self):
        self.check('''
local native=transport.fireFierce
transport.fireFierce=function(guard) packetTo(99);return native(guard) end
af.onBallSync();assert(fierceCalls==0)
''')
    def test_reversible_window_rescues_when_it_outlasts_impact(self):
        run_case(STACK + '''
startFierce();ability.Cooldown=1;ability.PendingPressAt=tm;ability.PendingPredictUntil=tm+.3
packetTo(42);assert(not cd.getDeflectCooldownState().miss)
af.onBallSync();assert(fierceCalls==1)
''')
    def test_predicted_reset_prevents_wasting_fierce(self):
        self.check('ability.PredictedResetUntil=tm+1;af.onBallSync();assert(fierceCalls==0)')
    def test_new_cooldown_episode_can_rescue_again(self):
        self.check('''
af.onBallSync();assert(fierceCalls==1)
ability.Cooldown=0;cd.getDeflectCooldownState();tm=tm+.1
ability.Cooldown=1;packetTo(42);af.onBallSync();assert(fierceCalls==2)
''')
    def test_teardown_removes_callbacks(self):
        self.check('af.teardown();heart:Fire(.016);assert(fierceCalls==0)')

if __name__ == '__main__': unittest.main()
