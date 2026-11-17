# Additional activation gate: danger in the next exchange

The feature is one additional candidate in AutoSpam.chooseActivation, after the existing return, close, self-return, dash and haunter candidates. It has no sender, delayed action, recovery controller or special active-session lifecycle. A selected candidate starts the existing Spam module through the original activate function. Activation and AP behavior remain separate from send continuity. Cooldown is observed as ability state, not treated as proof that an active local clash ended; confirmed far redirects stop the session immediately.

## Passive AP detector

AutoParry.getPressureDetector returns raw observations: the last accepted dispatch timestamp, ball, local target cycle, distance, speed, radial closing speed, trigger distance, frame duration, sync-gap envelope, ping and existing retry timestamp. It returns copies of dispatch samples. AP still makes its original firing, range, timing, retry and cancellation decisions. It performs no danger interpretation and sends no additional click for the detector. The session peak CPS is passive telemetry.

The 4.73 CPS stressed-clash observation belongs to AutoSpam's interpretation, where its reciprocal (approximately 211 ms) is a conservative service-capacity reference. This is not a new AP click interval, polling interval or cooldown. Frames, sync and network timing can increase the estimated service budget.

## Evidence and prediction

The gate tracks complete local return cycles (`local -> other target(s) -> local`), recent individual flight legs, and AP dispatch distances. A local target transition must have been observed; a newly generated ball simply appearing nearby is not evidence of a clash. Reset, pause and stopped-ball observations clear the added detector's history. Existing gates retain their own original rules, including the two-stud instant close gate.

The next cycle forecast includes the trend in observed cycle duration and an estimate from ball speed, player separation and relative approach velocity. The geometric estimate uses travel between players, rather than treating overlapping parry windows as an instantaneous round trip. This prevents a nearby slow ball from implying 25 required clicks per second. A stable short observed return and a sudden transition from slow to fast can both supply pressure evidence without an artificial wait for repeated confirmations.

Estimated AP headroom is calculated in AutoSpam from dispatch distance: nonnegative travel distance to the four-stud kill radius divided by closing speed, plus grace, minus uplink delay. A declining headroom forecast is corroborating evidence only when the next geometric exchange is also tight. A late current AP click or short current lethal deadline alone does not start spam.

When the next return is approaching, the additional gate may activate from:

- A measured/predicted local return cycle shorter than the AP service budget plus dispatch allowance.
- A short future geometric cycle corroborated by a recently observed fast flight leg.
- A small forecast AP margin combined with a tight future geometric cycle.

A candidate is evaluated immediately in the existing chooser. There is no extra timer, minimum click count, mandatory wait for the next target update, or separate handoff/recovery state machine. Active spam continues according to the original rules, regardless of whether this candidate is true on the next frame.

## Duplicate-click regression

The previous implementation could take a late AP dispatch or current proximity as a fresh instruction to start spam, and also added active-session recovery and sending-policy changes. A regression scenario reproduced two requests for one AP receipt on the previous main: the AP had already dispatched, while the next exchange was still safely outside its capacity limit. With future-exchange-only detection the same scenario produces only the original AP request. Actual dangerous returns still activate the existing spam sender immediately.

Scope verification compares original AP firing/timing/guard functions, Spam and Remote, and the existing activation candidates against commit 3a99342. The only firing-path AP addition records raw successful-dispatch observations. Active-send continuity was subsequently corrected for the specific cooldown and sync interruption paths described below.

## Physics and practical limits

The supplied dump confirms base/max ball speed 16/600 studs per second and a kill radius of 4 studs. StandardBall.GetTargetGrace starts with ping + 75 ms, with PressDelay affecting the cap; clash pressure can reduce grace toward 20 ms and the deflection window toward 30 ms. The grace countdown does not restart merely because the ball leaves the kill radius. The supplied 25 CPS ceiling corresponds to a 40 ms interval, but a client request is not proof of a server-accepted parry. Curves, abilities, replication and server rejection prevent a guaranteed survival claim from these estimates alone.

Info continues to display only measured peaks and useful current exchange data. Empty, invalid, non-finite and stale fields are hidden.

Tests execute the actual AP detector and AutoSpam/Spam code with explicit engine/network doubles: the reported double-click path, a safe next exchange despite a late current AP click, first short returns, slow-to-fast changes, return trends, tight next exchanges, preservation of original cooldown/lifecycle behavior, and repeated pure detector reads. These tests do not substitute for a live match.


## Active clash continuity at 13 studs

Two distinct interruption paths were reproduced:

1. `evaluate` and `canSend` immediately deactivated AutoSpam on `cooldown.blocking`. The `cooldown` reason bypassed the existing 14-stud proximity protection. Manual spam did not consult that block. The dump's client Deflect method still submits input when availability/cooldown prevents its local prediction branch; automatically stopping the sender is an additional restriction imposed by AutoSpam, not evidence of an ended clash.
2. `canSend` could return false on a temporarily uncertain target, old cached sequence or position disagreement while the active flag remained true. Thus the display could still say active despite interrupted requests.

The fix removes cooldown as an automatic session-stop condition in those two paths. Ability/remote processing, CPS handling and actual server acceptance remain unchanged. This preserves submission during the same local ability state in which manual spam continued submitting.

A short sync interruption can be bridged only after a real recent local round trip has been observed, while the same ball and living opponent remain within the existing proximity protection. The bound is based on the observed cycle plus network/frame allowance, clamped to 80–200 ms. It expires from the last actual exchange, and invalid snapshots cannot refresh it. This does not alter the activation gate, AP decisions, distance thresholds or configured sensitivity. Reset, pause, death, disable, ball replacement and invalid ball flags never use this bridge.

An explicit fresh valid target change to a third player outside the existing clash-distance boundary stops automatic spam in that same packet, even if the old opponent remains at 13 studs. This positive exit evidence takes priority over the proximity protection and continuity bridge. An old cached sequence cannot masquerade as a new far redirect.

`getStatus` exposes the last send-block reason/time and the last bridged-send time for diagnosis without adding empty Info panels.

A regression runs 12 simulated seconds with real AutoSpam, Spam and Cooldown modules, a 13-stud opponent, speed 600, target changes every 40 ms and 25 CPS configured. A reversible local cooldown is deliberately introduced at 7.96 seconds. Before the fix the session stops at 7.96 seconds with reason `cooldown`; afterward it stays active and keeps submitting. The chosen injection time reproduces the reported scenario; it does not establish the precise cause of an unrecorded live death. Additional tests cover manual/auto parity, cooldown changes inside one send batch, brief and expired sync loss, stale sequence caches, hard stops and immediate far redirects.

There is no eight-second AutoSpam timeout behind this reproduction. Clash pressure can shrink the server's defense/grace margins over time, making a previously survivable request gap fatal later. Live-match confirmation remains necessary.
