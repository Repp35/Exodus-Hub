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
