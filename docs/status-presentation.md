# Status presentation

`modules/front/app/status.luau` is the presentation module registered as `uistatus`. Its pure `format(data)` API accepts observations from module status APIs and returns the four existing Info panels: AP maximum CPS, AutoSpam gates, clash distance and travel time. It formats units, labels and ordering, and filters absent or non-finite values. It has no clock, game services, remote, detector or gate decisions and does not mutate input.

`controllers/telemetry.luau` remains the thin interface adapter: it reads enabled providers independently, passes their status objects to the presentation module, and updates the existing labels at 20 Hz. It retains the same fonts, panel positions, theme, padding, sizing and tween lifecycle. Provider failures clear only the affected panels, are logged once until recovery, and are retried on the next refresh. Closing/rebuild uses the existing connection scope.

AutoSpam's existing clash-status accessor now publishes travelElapsed and participant names. The interface no longer calculates elapsed time, reads raw ball snapshots, infers safety, or requires an active automated clash to show recorded measurements. Final clash results remain explicitly identified as final results until the collector replaces them. Disappearing provider data clears its text instead of retaining an old value.

Gate output includes actual collected common/selfReturn/dash/returnTarget/close/haunter/risk fields and the current activation reason, plus available return/margin measurements. Empty candidate defaults are omitted. AP maximum is shown only when the AP module supplies a finite positive measurement; the interface does not substitute the reported 4.73 CPS reference or a theoretical ceiling.

Regression tests exercise the actual UI for missing/invalid values, independent provider failure/recovery, gates without a valid ball snapshot, current value replacement, frozen collected results and producer-supplied elapsed time. The loader dependency contract includes the new module. Firing and gate behavior are outside this refactor.
