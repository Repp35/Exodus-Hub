# Native clash activation

AutoSpam enters only through GameInfo.getNativeClashContext(), which calls the actual GameBall:IsInClash(localPlayer). AP uses the same provider. LastParry attributes select the native pair, not an inferred activation. No target/window, animation, dash, Haunter, prediction, block timer or 40 ms block is required to enter.

The existing spam scheduler and configured cadence remain intact. Native activation sets the existing spam flag synchronously; its observer starts the scheduler without waiting for a physics frame. LastParry attribute events, runtime sync callbacks and the V14 AP opportunity callback all reach the native entry. The AP opportunity callback runs before AP dispatch arbitration, including when AP clicking is disabled. Old animation scanning and Haunter subscriptions are no longer installed.

Existing cooldown and physical exit behavior remain. Stops also cover opponent distance (35 studs), death, confirmed third-party redirect, match end, missing/replaced/reset ball, configuration and hub lifecycle. Freeze means BallData.Frozen, not a zero velocity or a visual frozen flag. Reset/lock states can still block sends. A sustained native flag cannot immediately undo an expired cooldown stop. Native false alone is not a new deactivation rule.

Target freshness/confirmation gates no longer delay the active native spam send path; lifecycle and deactivation checks run before sends. Lifecycle teardown cancels observers and scheduled sends through the existing scheduler generation guard.

Validation: 11 native provider/AutoSpam/scheduler tests, 7 V14 engine/adapter tests and 5 loader/API contract tests pass. The first send is verified inside the activation callback in deterministic mocks, including unavailable target and distant ball. These tests do not establish real Roblox latency or server acceptance. Historical tests of the removed activation heuristics are superseded by the native-entry suite; the repository already had broad unrelated failures before this change.
