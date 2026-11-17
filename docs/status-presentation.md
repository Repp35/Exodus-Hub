# Status presentation

`modules/front/app/status.luau` is the presentation module registered as `uistatus`. Its pure `format(data)` API accepts observations from module status APIs and returns the four existing Info panels: AP maximum CPS, AutoSpam gates, clash distance and travel time. It formats units, labels and ordering, and filters absent or non-finite values. It has no clock, game services, remote, detector or gate decisions and does not mutate input.

`controllers/telemetry.luau` remains the thin interface adapter: it reads enabled providers independently, passes their status objects to the presentation module, and updates the existing labels at 20 Hz. It retains the same fonts, panel positions, theme, padding, sizing and tween lifecycle. Provider failures preserve the last collected panel values, are logged once until recovery, and are retried on the next refresh. Closing/rebuild uses the existing connection scope.

AutoSpam's existing clash-status accessor now publishes travelElapsed and participant names. The interface no longer calculates elapsed time, reads raw ball snapshots, infers safety, or requires an active automated clash to show recorded measurements. Final clash results remain explicitly identified as final results until the collector replaces them. Disappearing provider data preserves the last collected values until newer measurements replace them.

Gate output contains exactly the last activation reason and last deactivation reason, each retained until its next event. AP output contains only the highest collected AP CPS. Clash Distance retains its most recent populated panel. Ball Travel retains independently the elapsed time/name of the observed target, time/name of the last completed target, and time/name of the last death. Starting a new clash does not erase a recorded death. Missing or invalid inputs never erase previous valid observations. Explicitly disabling a panel still hides it.

The added danger gate has one activation identifier, `exchange_danger`. Return cadence and dispatch margin are inputs to one combined decision, rather than two separately named activation reasons. Existing activation candidates retain their rules.

Regression tests exercise the actual UI for missing/invalid values, independent provider failure/recovery, gates without a valid ball snapshot, current value replacement, frozen collected results and producer-supplied elapsed time. The loader dependency contract includes the new module. Firing and gate behavior are outside this refactor.
