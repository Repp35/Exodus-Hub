# Smart Return

`smart_return` is one additional activation candidate after the original candidates. It uses a separate detector (`aux/smartreturn.luau`) with no sender, cooldown changes or active-session recovery controller. The existing activation candidates, active-send continuity, AP decisions and Info retention remain unchanged.

Required context: the ball must have targeted the local player, entered that player's configured AP full radius, left for another target, then returned to the local player. A first receipt, nearby spawn, or nearby opponent alone cannot qualify. An intermediate third target can return the ball, provided the complete local departure/return stays within the return budget.

At the default sensitivity of 50, the return budget is 200 ms measured from departure to return/window entry. This time does not scale with ball speed. The returning ball must be within the current AP full radius; only this acceptance radius is expanded by 20% when the returning opponent is strictly closer than 16 studs. The old gates' wider window helper and its bonus are not used by Smart Return.

The prior local visit records minimum observed ball distance. A matching passive AP dispatch sample can supplement that distance and supplies the actual trigger radius. Penetration is `(full radius - minimum distance) / (full radius - kill radius)`, clamped to 0–1. Zero means a deflection at the full-radius boundary; one means reaching the kill radius. A worsening penetration relative to the preceding visit and a shorter actual return increase the score. Neither the first appearance nor current proximity alone supplies this history.

Sensitivity is configurable in Settings, Parry & Camera, from 0 to 100. Default 50 gives a score threshold of 0.40 and a 200 ms budget. At 0, the threshold is 0.65 and the budget 160 ms; at 100, the threshold is 0.15 and the budget 240 ms. Increasing sensitivity accepts less severe historical penetration and a wider approximation around the AP's 200 ms reference. Radius expansion remains exactly 20%, independent of sensitivity.

Score = prior penetration + positive worsening + 0.25 × remaining fraction of the return budget. A current AP dispatch recorded after the arrival invalidates a still-pending candidate, preventing a late extra activation for that same receipt. There is no artificial wait for additional samples: the first context-complete, qualified return can activate the existing spam sender immediately. Reset, invalid data, ball replacement and clock reversal clear the detector.

These are context and pressure estimates, not a measured probability of death. Tests cover the pure detector and production AutoSpam/Spam integration, including precise AP deflections, slow returns, radius expansion, sensitivity, deepening visits, third targets, reset and duplicate-click avoidance. Live-match validation is still needed.
