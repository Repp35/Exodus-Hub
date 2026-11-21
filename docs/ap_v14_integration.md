# V14 AP integration

The V14 runtime is implemented directly inside AutoParry, with no extra loader module. The engine uses the V14 native snapshot hook, multiple target sources, two-render-frame visual validation, native trajectory simulation, relative closing velocity, one-way ping and adaptive window factor. Match window is 500–300 ms. Training retains its native window and Block remote, including UnreliableRemoteEvent BallState support.

Hub dispatch is one call per validated incoming flight. Clash repetition is excluded. A confirmed own parry plus a newer inbound snapshot can establish a new flight when the away packet was lost. Predicted parries cannot rearm. The existing opportunity notification is retained. The follow-up native AutoSpam integration replaces activation rules with the native clash provider; see native_clash_autospam.md.

AutoParry owns engine teardown and rebind. The engine creates no UI. The loader uses its existing AutoParry entry; there is no DefenseEngine dependency.

Validation: seven actual-engine/adapter mock tests and five loader/API contract tests pass. Full unittest comparison against commit 3ca4d8be has no additional failures: both have 189 failing cases and nine errors already present in the baseline. These offline tests do not establish live latency or server acceptance. Roblox match/training testing is still required.

AP cooldown recovery is restored: the native match dispatch checks the existing cooldown provider. A completed miss tied to the latest attempt can rearm the same target without requiring an away/return edge. Confirmed parries and old miss records cannot rearm. Target and physical window are reevaluated before retry. Eight runtime/adapter tests now cover this recovery.
