# Return with kill-radius cycles

One additional activation gate, `return_kill_cycles`, uses the existing return window check and a fixed 200 ms timer. There is no AP dependency, speed-scaled timing, score, sensitivity setting or prediction.

A local target departure starts the timer only when the last local observation had the ball in the window. During that same timer the ball must return to the local player already within the full radius, and complete at least two observed inside -> outside -> inside cycles of the kill radius (normally 4 studs). Repeated samples on the same side do not count. No inferred crossings are added between samples. The timer does not restart when another departure happens before its deadline. Activation also requires the local player to be the current target, the current window check to pass and the ball to be inside the full radius.

The first inside observation can precede the timer: the departure can supply the first exit, followed by a return entry. Starting outside the kill radius does not count as having exited it. Reset, ball replacement, backwards clock or missing observations longer than 200 ms clear the context.

Only a session activated by this gate gets `return_exchange_timeout`: activation starts a 100 ms exchange deadline, refreshed only by an observed local-player -> partner or partner -> local-player target change. Repeated same-target updates, stale sequences and unrelated third targets do not refresh it. When the deadline is exceeded, the session stops unless the partner is at most 5 studs away. Leaving that exception without a fresh exchange allows immediate timeout. This dedicated reason bypasses the older 14-stud protection; other gates retain their original behavior. Existing death, disable and confirmed far-redirect stops still apply.

The activation consumes its crossing evidence; an expired session cannot reactivate using the same old crossings. Observation for this activation gate is reset while spam is already active. The AP and the existing spam sender are unchanged.

Tests cover literal crossing counts, the fixed timer, target/window requirements, context reset, immediate sender activation, the dedicated timeout, its five-stud exception, same-target and unrelated-target updates, preservation of legacy activation behavior, and evidence consumption. Sampling can miss a crossing between observations; the gate deliberately does not invent one. No live-match survival guarantee follows from these tests.
