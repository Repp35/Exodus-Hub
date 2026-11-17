# Removed additional danger gate

The additional `exchange_danger` activation gate has been removed at the user's request. AutoSpam no longer calculates danger deadlines, predicts future cycles for activation, reads AP pressure telemetry, exposes a risk status object or depends on AutoParry.

The original activation candidates remain: consistent self-return, dash, return-target, close-target and haunter. Their conditions and order are unchanged. The original close-target candidate may still activate at two studs; removing the additional gate does not change that rule.

Actual target cycles are observed only to preserve the previously fixed active-send continuity during brief sync gaps. That collector has no activation return path. The cooldown interruption correction and immediate confirmed far-target exit remain in place.

Info persistence and the AP peak measurement remain available. The AP firing logic and spam sender are unchanged by this removal.
