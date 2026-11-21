# AutoSpam session lifecycle (v6)

AutoSpam recognizes exchanges; Spam remains the only high-rate sender. AP's
modular scheduler preserves exclusive dispatch while Spam is active. Configured CPS/CPF and transport are
unchanged. The module no longer contains disconnected animation, dash, Haunter,
prediction or legacy activation implementations. Public compatibility methods
used by other modules remain available.

## Evidence and entry

One ordered target-leg tracker consumes packet and explicit target-attribute
transitions. Observing a snapshot does not mark its packet event as processed.
Duplicate target values do not create another leg; duplicate/old network packets
are rejected with uint16 wrap ordering. A return belongs to one ball and leg.
If it arrives outside the entry geometry, it remains pending until entry,
replacement or expiry. Return pressure uses the geometry's effective window,
network estimate and frame interval instead of the old fixed 150 ms cutoff.
This is an observation budget, not an assumed AP CPS or measured response SLA.

Native/context entry retains partner/contact checks. Tight entry may anticipate
before the local player becomes the target. A stale own parry plus an ordinary
inbound approach cannot start it. The context provider is GameInfo.getClashStatus
(local LastParry attributes), not a call to the game's IsInClash method.

## Exit and rearm

A session stops for lifecycle changes, third-party redirect, invalid/stale
geometry, sustained cooldown or physical departure past both players. An
outgoing leg toward the current partner does not by itself end a clash.
Every send still goes through AutoSpam.canSend, so cancellation does not wait
for a later render/physics callback.

Stopping records the consumed target leg and parry stamp and cancels the pending
return. The same context cannot reopen the session when distance jitters back
inside the window. A new valid return or newer parry can rearm immediately;
there is no arbitrary sleep/debounce. A cooldown stop also records its episode;
a new candidate cannot reset that episode's deadline. Confirmed misses block all
entry paths, while predicted reset/reversible cooldown does not block a real
return. Ball replacement resets ball-specific evidence.

## Validation and limits

`test_autospam_lifecycle_v6.py` exercises the real AutoSpam with the real Spam
scheduler and explicit engine doubles: immediate dispatch, pre-read packet
ordering, attribute-only returns, echo deduplication, pending evidence,
expiry/wraparound, stale-context hysteresis, fresh-event rearm, outward clash
continuity, departure/redirect cancellation and cooldown ownership. The fast
return tests now cover valid attribute evidence and the geometry-based budget.
API contract and integrated AP engine tests check compatibility.

These tests do not replay the unrecorded inputs of the submitted video and do
not measure Roblox server acceptance, FPS or guarantee zero misses. Full-suite
baseline failures must be reported separately from these focused regressions.
