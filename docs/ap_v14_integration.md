# V14 AP integration

The loader injects DefenseEngine into AutoParry. The engine uses the V14 native snapshot hook, multiple target sources, two-render-frame visual validation, native trajectory simulation, relative closing velocity, one-way ping and adaptive window factor. Match window is 500–300 ms. Training retains its native window and Block remote, including UnreliableRemoteEvent BallState support.

Hub dispatch is one call per validated incoming flight. Clash repetition is excluded. A confirmed own parry plus a newer inbound snapshot can establish a new flight when the away packet was lost. Predicted parries cannot rearm. AutoSpam activation rules and click scheduler are unchanged; the existing opportunity notification is retained.

AutoParry owns engine teardown and rebind. The engine creates no UI. Direct legacy consumers without the loader keep the previous adapter; the loader contract requires the new engine.

Validation: seven actual-engine/adapter mock tests and five loader/API contract tests pass. Full unittest comparison against commit 3ca4d8be has no additional failures: both have 189 failing cases and nine errors already present in the baseline. These offline tests do not establish live latency or server acceptance. Roblox match/training testing is still required.
