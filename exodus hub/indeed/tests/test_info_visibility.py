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
apStatus.maxObservedCps=math.huge;tick();assert(label('APMaxCps').Text=='AP max: 4.73 CPS')
apStatus.maxObservedCps=2;tick();assert(label('APMaxCps').Text=='AP max: 4.73 CPS')''')

    def test_invalid_numbers_are_not_rendered(self):
        self.check('''valid=true;snapshot={syncSpeed=0/0,speed=math.huge}
status={active=true,clashStats={currentCps=0/0,lastTravelTime=math.huge,endSample={distance=0/0}},
 risk={exchangeEvidence=true,observedCycle=math.huge,nextCycle=0/0,response=math.huge,nextHeadroom=0/0}}
tick();empty('ClashDistance');empty('ClashTravelTime')
empty('AutoSpamGateInfo')''')

    def test_new_values_replace_previous_and_missing_data_retains_last(self):
        self.check('''valid=true;snapshot={speed=300}
status={active=true,lastActivationReason='return_demand_exceeds_ap',
 clashStats={endSample={distance=12,speed=300},lastTravelTime=.18,currentCps=5},
 risk={exchangeEvidence=true,observedCycle=.27,nextCycle=.22,response=.211}}
tick();assert(label('ClashDistance').Text:find('12.0 studs',1,true))
assert(label('AutoSpamGateInfo').Text=='Last activation: return_demand_exceeds_ap')
status.clashStats.endSample.speed=400;status.clashStats.endSample.distance=8
status.risk.observedCycle=.2;status.risk.nextCycle=.16;tick()
assert(not label('ClashDistance').Text:find('12.0 studs',1,true))
assert(label('ClashDistance').Text:find('Speed: 400',1,true))
assert(not label('AutoSpamGateInfo').Text:find('270 ms',1,true))
status={};tick()
assert(label('ClashDistance').Text:find('Distance: 8.0 studs',1,true))
assert(label('ClashTravelTime').Text:find('Last target: 180 ms',1,true))
assert(label('AutoSpamGateInfo').Text=='Last activation: return_demand_exceeds_ap')''')

    def test_collected_final_result_is_visible_without_live_ball(self):
        self.check('''status={clashStats={frozen=true,deceasedName='You',fatalTravelTime=.07,
 penultimateTravelTime=.09,lastTravelTime=.1,endSample={distance=5,speed=600},currentCps=20}}
tick();empty('AutoSpamGateInfo')
assert(label('ClashDistance').Text:find('Final distance: 5.0 studs',1,true))
assert(label('ClashTravelTime').Text:find('Last death (You): 70 ms',1,true))''')

    def test_latest_gate_events_are_retained_and_replaced(self):
        self.check('''status={lastActivationReason='return_target',gates={selfReturn='ready'},risk={observedCycle=.2}}
tick();assert(label('AutoSpamGateInfo').Text=='Last activation: return_target')
status={lastActivationReason='return_target',lastStopReason='target_redirected_far'};tick()
assert(label('AutoSpamGateInfo').Text=='Last activation: return_target\\nLast deactivation: target_redirected_far')
status={lastActivationReason='dash_incoming',lastStopReason='target_redirected_far'};tick()
assert(label('AutoSpamGateInfo').Text=='Last activation: dash_incoming\\nLast deactivation: target_redirected_far')
deps.AutoSpam.getStatus=function() error('temporary') end;tick()
assert(label('AutoSpamGateInfo').Visible)
assert(label('AutoSpamGateInfo').Text=='Last activation: dash_incoming\\nLast deactivation: target_redirected_far')
deps.AutoSpam.getStatus=function() return {lastActivationReason='null'} end;tick()
assert(label('AutoSpamGateInfo').Text=='Last activation: dash_incoming\\nLast deactivation: target_redirected_far')''')

    def test_provider_failure_does_not_break_other_panels_and_recovers(self):
        self.check('''apStatus.maxObservedCps=4.73
deps.AutoSpam.getStatus=function() error('temporary provider failure') end
tick();assert(label('APMaxCps').Visible);empty('ClashDistance')
deps.AutoSpam.getStatus=function() return {clashStats={endSample={distance=13}}} end
tick();assert(label('ClashDistance').Text=='Distance: 13.0 studs')''')

    def test_travel_uses_collected_elapsed_not_ui_clock(self):
        self.check('''status={clashStats={travelElapsed=.123,travelTargetName='You'}}
tick();assert(label('ClashTravelTime').Text=='Target (You): 123 ms')
tm=tm+10;tick();assert(label('ClashTravelTime').Text=='Target (You): 123 ms')
status.clashStats.travelElapsed=.2;tick()
assert(label('ClashTravelTime').Text=='Target (You): 200 ms')''')

    def test_all_last_metrics_survive_missing_provider_and_new_clash(self):
        self.check('''apStatus.maxObservedCps=4.73
status={clashStats={endSample={distance=13,speed=600},travelElapsed=.04,travelTargetName='You',
lastTravelTime=.08,lastTravelTargetName='Opponent',fatalTravelTime=.06,deceasedName='You'}}
tick();local travel=label('ClashTravelTime').Text;local distance=label('ClashDistance').Text
assert(travel:find('Last target (Opponent): 80 ms',1,true))
assert(travel:find('Last death (You): 60 ms',1,true))
deps.AutoSpam.getStatus=function() error('temporary') end
deps.AutoParry.getStatus=function() error('temporary') end
for i=1,5 do tick() end
assert(label('APMaxCps').Visible and label('ClashDistance').Text==distance)
assert(label('ClashTravelTime').Visible and label('ClashTravelTime').Text==travel)
deps.AutoSpam.getStatus=function() return {clashStats={travelElapsed=.02,travelTargetName='Opponent'}} end
tick();assert(label('ClashTravelTime').Text:find('Target (Opponent): 20 ms',1,true))
assert(label('ClashTravelTime').Text:find('Last death (You): 60 ms',1,true))
assert(label('ClashTravelTime').Text:find('Last target (Opponent): 80 ms',1,true))''')

if __name__=='__main__':unittest.main()
