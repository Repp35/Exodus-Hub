# AutoParry timing

The timing follows the client APIs inspected in the supplied `SrcDump_olym4`:

- `Shared.Abilities.DeflectAbility.estimateWindow`: 0.85 seconds at speed 16, decreasing to 0.20 at speed 600. Clash applies its minimum window and pressure; full pressure can reduce it to 0.03 seconds.
- `GameBall.GetKillDistance`: 4 studs. The base parry range is 8.5; resilience and close rally rules determine the current range.
- `BallReplicator.SimulateFrom`: movement includes steering, acceleration, speed feel, bounces and grace. The drawn ball also has interpolation offsets and a grace hold position, so its visual distance alone is insufficient for timing.
- `DeflectAbility.Deflect`: calls less than 0.008 seconds apart are refused. A nil return can mean either a successful send or an early return.

## Position and decision

`GameInfo.getSnapshotAt` keeps its visual snapshot behavior for existing consumers. `getParrySnapshot` separately samples the replicator at current server time and again 1/240 second later to estimate current velocity. It preserves the packet's simulation metadata if the hub callback runs before the game's callback. Prediction is cached with the snapshot and is limited to fresh, unlocked packets targeted at the local player. Missing simulator support falls back to the existing snapshot checks.

The AP uses relative motion to estimate entry into the actual parry range and the kill radius. A ball moving away does not consume a parry outside the raw range. Inside the raw range, a ready cooldown and confirmed target still permit an emergency click.

The configured base factor is respected. The factor rises toward 0.85 when the travel time from the parry radius to the kill radius is smaller than the frame/response budget, or when the current time to the kill radius becomes small. This is recalculated for each decision and does not overwrite the saved configuration.

One-way network delay is added separately. Frame compensation plus the selected portion of the window is capped at 95% of the current game window, preventing compensation from extending a 30 ms pressured window into an invalid earlier click. The ordinary tick, final send guard, redirect path and timing getters use the same decision calculation.

Client refusal leaves the AP armed and uses the available retry delay instead of an unconditional 30–50 ms wait. The Remote adapter checks click registration to distinguish the inspected client's nil rejection from a successful nil return.

## Validation and limits

Targeted checks cover 30/60/144/240 FPS, high speed, pressured windows, visual/server position disagreement, callback ordering, packet metadata, adaptive safety margins and short client-throttle retries. These use explicit engine doubles, including a simulator double; they do not reproduce Roblox's complete physics or networking. The production path delegates curved motion to the game's simulator instead of replacing it with a linear approximation.

The predictor has bounded packet age and a visual fallback. Cooldown, frozen/reset state, late packets, scheduler stalls and server changes can still prevent a successful parry. No timing factor can guarantee survival under every network or frame stall.
