# Modular defense (AP v15)

The embedded V14 engine and the second, mostly bypassed AP implementation have
been replaced by one flight scheduler. AutoParry no longer imports game modules,
hooks `BallReplicator.ApplySnapshot`, decodes packets, resolves target votes,
simulates trajectories, or computes defense radii/windows. Existing loader entry
and public action/status endpoints remain available.

| Owner | Responsibility |
| --- | --- |
| BallSync | Decode, validate and order network observations |
| Targeting | Resolve target metadata and safe fallback sources |
| GameInfo | Membership, current observations, shared native simulation cache |
| DeflectGeometry | Native base, parameterized relative trajectory, radius and collision/kill timing |
| Cooldown | Readiness, attempts, confirmation, reversible windows and recovery |
| AutoParry | Own window/factor policy, flight ownership, dispatch, rearm and cancellation |
| AutoSpam / Spam | Exchange/session authorization / configured high-rate sending |
| AutoFierce | Emergency decision when Deflect cannot recover before impact |
| Remote | Transport and final guard; optional native acceptance observation for AP |

AP observes target legs while Spam owns sending. Its final guard checks ownership
again, so an opportunity which starts Spam cannot also send an AP click. Handover
ignores the final Spam native press as a manual click. Native refusals do not
spend the flight and do not install an arbitrary retry delay. A completed miss
associated with the current attempt can rearm the same target. A successful
confirmation needs a later incoming snapshot; each confirmation is consumed once.

Native trajectory simulation, relative player motion, ping, adaptive cadence,
physical-range fallback, training Block transport and character lifecycle remain
in the modular pipeline. AP defines its own 500–300 ms base and fractional,
adaptive factor. Geometry retains the native 850–200 ms base. Each consumer
supplies its own window, factor, latency and optional lead cap; these overrides
do not mutate the native base or another consumer. AP also keeps its clash
pressure adjustment and training policy inside AP.
Trajectory timing outside physical range requires an actual sphere intersection.
Training uses GameInfo's existing state/events and Cooldown's training lockout.

Target metadata conflicts use local receive timestamps. A stale target attribute
cannot permanently veto newer accepted packets, and a newer attribute can take
over until a later packet. Visual colors/provider positives cannot override an
explicit current opponent ID. Expired packets expose no current exchange ID.

Fierce uses the same eligible snapshot and geometry as AP. Cooldown decides
whether ordinary defense is ready, failed, or still reversible but too late for
an imminent impact. The send guard recomputes these conditions; a finished
cooldown cannot trigger an unnecessary rescue. A rescue stops AutoSpam, and one
successful Fierce dispatch is allowed per cooldown episode. Manual Fierce does
not install a five-second AP pause or modify native ability methods.

The normal Spam sender, configured CPS/CPF and expected client/server refusals
are unchanged. AP alone uses `Remote.fireCheckedParry`: native press timestamp
changes are evidence of a client attempt, never proof of server acceptance.
Direct/Input modes report submission because they expose no native confirmation.

## Validation

`test_defenseengine.py` runs production GameInfo, Targeting, BallSync,
DeflectGeometry, Cooldown, Remote, AP and Fierce together. Roblox instances,
network events and native abilities are doubles. Its training cases exercise the
real training observers and Block route. The focused Fierce/miss/authorization
checks use this shared fixture rather than extracting private functions from AP.
AutoSpam regressions also run the production Spam scheduler.

The repository-wide suite has pre-existing failures and must be compared against
the untouched parent, not described as green. Offline tests do not reproduce all
unrecorded game inputs from the video, measure live scheduling latency, or prove
zero misses. Match/training validation in Roblox remains necessary.
