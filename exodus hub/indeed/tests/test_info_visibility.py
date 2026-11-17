"""Execute the real Info controller and inspect content after live status changes."""
import unittest
import test_ui_library as ui

SETUP = '''
local tm=10;os.clock=function() return tm end
config.ClashGateInfoVisible=true;config.ClashDistanceVisible=true
config.ClashTravelTimeVisible=true;config.APMaxCpsVisible=true
local status,apStatus,snapshot={}, {}, {}
local valid=false
local deps=fullDeps()
deps.AutoSpam.getStatus=function() return status end
deps.AutoParry.getStatus=function() return apStatus end
deps.GameInfo.getSnapshotAt=function() return snapshot end
deps.GameInfo.isSnapshotValid=function() return valid end
assert(ui.setup(deps,{open=true}));flushDeferred();finishTweens()
local function tick()
 tm=tm+.1;game:GetService('RunService').Heartbeat:Fire(.1);finishTweens()
end
local function label(name) return findDescendant(playerGui,name) end
local function empty(name)
 local x=label(name);assert(x and x.Text=='' and not x.Visible,name..' retained empty/stale Info')
end
'''

class InfoVisibility(unittest.TestCase):
    def check(self,case):
        ui.UILibraryTests().run_lua(SETUP+case)

    def test_idle_info_has_no_waiting_failures_or_placeholders(self):
        self.check('''status={lastGate='no_activation_evidence',gates={dash='dash_no_partner',close='close_not_target'}}
apStatus={pressureReferenceCps=4.73,estimatedCapacityCps=4.73}
tick();for _,name in ipairs({'APMaxCps','AutoSpamGateInfo','ClashDistance','ClashTravelTime'}) do empty(name) end''')

    def test_peak_only_shows_an_actual_finite_measurement(self):
        self.check('''apStatus={maxObservedCps=0/0};tick();empty('APMaxCps')
apStatus.maxObservedCps=4.73;tick()
assert(label('APMaxCps').Text=='AP max: 4.73 CPS')
assert(label('APMaxCps').Visible)
apStatus.maxObservedCps=math.huge;tick();empty('APMaxCps')''')

    def test_invalid_numbers_are_not_rendered(self):
        self.check('''valid=true;snapshot={syncSpeed=0/0,speed=math.huge}
status={active=true,clashStats={currentCps=0/0,lastTravelTime=math.huge,endSample={distance=0/0}},
 risk={exchangeEvidence=true,observedCycle=math.huge,nextCycle=0/0,response=math.huge,nextHeadroom=0/0}}
tick();empty('ClashDistance');empty('ClashTravelTime')
assert(label('AutoSpamGateInfo').Text=='Auto Spam: Active')''')

    def test_new_values_replace_previous_values_and_reset_clears_them(self):
        self.check('''valid=true;snapshot={speed=300}
status={active=true,activationReason='return_demand_exceeds_ap',
 clashStats={endSample={distance=12},lastTravelTime=.18,currentCps=5},
 risk={exchangeEvidence=true,observedCycle=.27,nextCycle=.22,response=.211}}
tick();assert(label('ClashDistance').Text:find('12.0 studs',1,true))
assert(label('AutoSpamGateInfo').Text:find('270 ms',1,true))
snapshot.speed=400;status.clashStats.endSample.distance=8
status.risk.observedCycle=.2;status.risk.nextCycle=.16;tick()
assert(not label('ClashDistance').Text:find('12.0 studs',1,true))
assert(label('ClashDistance').Text:find('Speed: 400',1,true))
assert(not label('AutoSpamGateInfo').Text:find('270 ms',1,true))
snapshot.resetting=true;tick()
for _,name in ipairs({'AutoSpamGateInfo','ClashDistance','ClashTravelTime'}) do empty(name) end''')

    def test_completed_clash_does_not_leave_old_fields_on_screen(self):
        self.check('''valid=true;snapshot={speed=600}
status={clashStats={frozen=true,lastTravelTime=.1,endSample={distance=5},currentCps=20},
 lastActivationReason='return_target',lastStopReason='ap_recovered'}
tick();empty('AutoSpamGateInfo');empty('ClashDistance');empty('ClashTravelTime')''')

if __name__=='__main__':unittest.main()
