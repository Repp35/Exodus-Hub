# Auto Spam: deadline prediction

The supplied SrcDump_olym4 sources confirm:

- GameBall.GetKillDistance: 4 studs; base/max speed: 16/600.
- StandardBall.GetTargetGrace: clamp(ping + 75 ms, 75 ms, 350 ms), with PressDelay + 50 ms extending the upper bound to 450 ms.
- GameBall.ApplyClashPressureGrace reduces grace toward 20 ms. ApplyClashPressure reduces the deflection window toward 30 ms. Pressure grows after two seconds over eight seconds, provided the clash has at least two hits.
- StandardBall.CheckDeadOrParry starts a grace countdown on lethal contact. It checks an active DeflectingWindow before killing. Leaving the radius does not restart an already running grace countdown.
- BallReplicator simulates steering, bounces and movement in substeps. Straight-line interception alone cannot rule out danger.
- 25 effective CPS (40 ms) is the user-supplied game ceiling; the dump also has client call throttling and queued presses, so calls sent are not proof of server-accepted parries.

## Detection

The priority gate compares the earliest plausible lethal deadline with the AP response budget plus a 40 ms dispatch margin. Incoming prediction uses sphere intersection with relative velocity and a conservative homing arrival bound. Outbound prediction estimates the opponent's earliest legal deflection and immediate return, including speed gain and relative player movement. These are conservative bounds, not a complete recreation of server physics.

The AP response budget includes observed frame duration, an envelope of sync gaps, one-way latency, a server-frame allowance, retry deadlines and blocking cooldown. With no sync measurement, the initial sync allowance is 50 ms. CPS observed during ordinary play is displayed separately and is never used as an AP capacity limit. AP estimates and observed peaks are capped at 25 CPS. No benchmark injects artificial clicks during a match.

Once local lethal contact or replicated Grace is observed, grace remains latched until target/reset changes. Replicated grace has no authoritative expiry timestamp; its remaining time is conservatively reduced by snapshot age and uplink latency. The server may already have started grace before the client sees it.

## Continuity fixes

Cooldown no longer turns off automatic spam or suppresses its calls, matching manual spam's continuous send policy. The ability/server can still reject a call. A dangerous third-player handoff changes the tracked partner without stopping spam. Brief uncertain/stale packet states can bridge at most 100 ms from the last valid sample; death, pause, teleport and reset never use this bridge. Lifecycle teardown now clears the spam flag even near an opponent.

Existing return, dash and haunter evidence remains available as fallback. Risk is evaluated first, so a first dangerous approach does not need a confirmed round trip. The Info overlay exposes deadline versus AP budget and separates game maximum, observed AP peak and estimated AP capacity.

## Validation and limits

Tests execute the production AutoSpam and Spam code with simulated engine/network inputs: first approach, possible return, movement and dash-speed approach, third-player handoff, cooldown, uncertainty expiration, reset/pause, curved directions, latched grace, teardown and a 36-scenario speed/grace/frame-phase grid. AP timing, contracts and UI suites are checked separately. These tests do not prove survival against a live server, packet loss, unknown abilities or misses.

Some legacy gate tests demand delayed activation until a round trip or stopping on a miss; those expectations conflict with continuous spam and early risk activation. The legacy suite also fails on the original checkout. No 100% survival guarantee follows from the reported match percentages or from the 25 CPS ceiling. In particular, 20 ms grace alone is shorter than a 40 ms click interval: an already active defense window and anticipation matter.

## Revision: 4.73 CPS observed under clash pressure

The user clarified that 4.73 CPS was the fastest cadence observed with high ball speed and the opponent inside the window, just before death. Its reciprocal, approximately 211.4 ms, is now the initial conservative effective service interval for a stressed AP. It is not evidence that frames, sync or ball perception literally occur every 211 ms. Ordinary quiet-play click intervals must not be used to measure processing capacity. The service budget is the larger of this reference and the frame/sync/network budget; slower live conditions can increase it.

### Capacity, demand and remaining margin

A complete sequence `local target -> other target(s) -> local target` supplies one observed local return cycle. One target switch supplies only a leg. The next observed cycle is forecast as `latest + min(0, latest - previous)`, with stale evidence expiring after 750 ms. Third-player changes do not discard an ongoing local return episode.

The physical forecast also projects player separation one service interval ahead and estimates the cycle between legal parry ranges using relative approach velocity and the next ball speed. This is deliberately conservative and can activate earlier than necessary. Raw player velocity captures ordinary approach and dash movement, including an opponent catching a retreating local player. Existing dash-event prediction remains a fallback before velocity replication is available.

Each accepted AP dispatch now records ball identity, timestamp, distance, trigger distance and estimated headroom: `(distance - kill radius) / closing speed + grace - uplink`, with nonnegative travel distance. This is dispatch telemetry, not confirmation that the server accepted the parry. Consecutive samples allow forecasting a further loss of headroom instead of waiting for the final failing return. Rejected requests and training clicks do not supply these samples.

Auto Spam takes over if any of these conditions holds:

1. The present lethal deadline is within the AP service budget plus the existing 40 ms dispatch allowance.
2. A return is approaching within two service budgets and its forecast cycle demands a cadence beyond the AP budget plus allowance.
3. A return is approaching and the next estimated AP headroom falls within that budget plus allowance.

For example, local return cycles of 320 ms then 270 ms forecast approximately 220 ms on the next exchange. A 211 ms AP has almost no reserve there; waiting to observe a 200 ms failed exchange would be late. Likewise, headroom samples of 350 ms then 270 ms forecast 190 ms remaining on the next comparable dispatch. These are examples, not required sample patterns or a fixed 'penultimate parry' counter.

The takeover starts the existing Spam sender immediately. AP requests already have a dispatch guard against spam; the two consumers share the same remote without intentionally issuing competing requests. Spam keeps ownership while risk persists. A pressure-triggered session can return control after comfortable margins remain stable for 250 ms, with wider release thresholds to prevent toggling. Any renewed pressure resets that recovery timer. Reset, pause and death protections remain in force.

The Info overlay exposes the externally reported reference separately from the session peak and runtime-adjusted clash estimate, along with required return cadence, forecast headroom and dispatch/trigger distances. The earlier statement that the AP model uses only frame/sync timing is superseded by this revision. No 100% survival guarantee or exact inference of the final two parries is possible from these measurements alone.

### Additional validation

Behavioral tests cover predictive takeover while the current return is still outside the lethal threshold, shrinking dispatch margins, full local cycle trends, rejection of single-leg CPS inference, expiration of old evidence, first fast approaches without history, actual AP dispatch sampling, stable release back to AP and renewed-pressure cancellation of release. They complement the original 36-condition deadline grid. No live game session was available for validation.
