"""A native burst must not insert an empty interval after its initial click."""
import unittest
from autospam_harness import check

class NativeClickCadence(unittest.TestCase):
    def test_second_click_is_due_after_one_interval(self):
        check('''
packet(42,0,2);assert(clicks==1)
heartbeat(.04);assert(clicks==1)
heartbeat(.002);assert(clicks==2,'initial click delayed the second by an extra interval')
''')
