# Momentum implementation status and remaining gaps

**Audit target:** `agent/continue-momentum`
**Starting point:** `b0686438add7ff62a137e5d4145684030a6dd6d5`
**Last implementation pass:** 2026-08-02
**Normative sources:** `docs/PRODUCT-SPEC.md`, `docs/TECHNICAL-SPEC.md`, and `docs/DESIGN.md`

This document supersedes the earlier audit of `b0686438`. The branch now contains the implementation work described below. It intentionally separates code that is complete from work that still needs implementation and from release checks that require Apple infrastructure or a physical device.

## Executive status

The primary offline product is implemented and builds successfully. Today, workout logging, nutrition, care, History, Plans, Progress, Settings, export, reconciliation, and actionable notifications are connected to persisted data. The highest-risk correctness gaps from the prior audit—missed-day reconciliation, notification routing, post-workout care, History/correction, plan editing, real adherence presentation, Progress charts, unit behavior, and settings runtime behavior—have been addressed.

The branch is not yet release-certified. Remaining product work is concentrated in CloudKit conflict UX/verification, a small set of advanced correction and milestone flows, and broader automated/manual validation.

## Implemented in this pass

### Scheduling and reconciliation

- Deterministic canonical settings selection, including a UUID tie-breaker.
- Duplicate settings cleanup during seed/bootstrap.
- Deterministic care-occurrence duplicate repair that preserves the strongest recorded intent.
- Care duplicate keys include routine role and source workout session, so distinct post-workout occurrences are retained.
- One Missed Workout event is created for every elapsed Due opportunity, including an active session that crosses the cutoff.
- Missed and skipped days keep the same workout due; they do not advance the cycle.
- Care role snapshots remove name-based runtime identity.
- Alternating hair-care recurrence advances from the actual completion Domain Day and can be undone.
- Reconciliation runs after the primary mutations that affect reminders or adherence.

### Notifications

- Workout Start actions route to Today and start the identified current opportunity.
- Overdue reminders use the current notification Domain Day rather than a stale original due day.
- Night-care and unfinished-nutrition reminders coalesce only when their times match.
- Care Done uses the centralized, idempotent completion mutation.
- Notification scheduling health is persisted as healthy/failed and surfaced in Settings.
- Scheduling errors no longer roll back otherwise-valid settings.

### Today and workout session

- Recovery Start Early shows remaining recovery and requires factual confirmation.
- Notification routes are consumed by Today and open the appropriate workout.
- Food rows expose edit, duplicate, and delete actions without relying on unsupported ScrollView swipe behavior.
- Completed, skipped, missed, and post-workout care states are represented explicitly.
- Today now uses a real 7-row-by-16-week adherence heatmap plus workout, nutrition, and care streaks.
- Working weights flow from plan prescriptions into newly created set logs.
- Previous-set lookup ignores deleted source sessions.
- Finishing a workout refreshes schedule/reminders.
- Post-workout questions generate idempotent Wash Face and conditional Reapply Sunscreen care.
- Post-workout body weight and set logging respect metric or imperial display/input while persistence remains metric.

### History and correction

- All-category and filtered 16-week heatmap with older/newer navigation.
- Accessible per-cell Domain Day, score, completed count, and due count.
- Workout-opportunity, nutrition-day, and care-day streak projection from persisted facts.
- Chronological day detail for workout, nutrition, food, care, and measurements.
- Food editing and backdating.
- Measurement backdating.
- Confirmed soft deletion for food, measurement, and completed workout facts.
- Visible same-screen Undo for supported deletions.
- Completed-workout deletion preview shows the before/after next workout and due day without mutating first.
- Accepted corrections reconcile adherence, schedule, and reminders.
- History measurement values respect the selected unit system.
- Completed workout timestamps can be edited/backdated after a non-mutating before/after schedule preview; logged sets remain explicitly unchanged.
- Past Nutrition Days can be finalized or reopened directly from History.
- Completed care can be undone directly from History, including alternating-recurrence rollback.
- Correction mutations run through transaction-focused services and tests.

### Plans

- Reorder the active Workout Cycle with contiguous sequence indices.
- Select the next workout anchor.
- Edit workout focus and recovery days.
- Add, edit, reorder, and archive exercises.
- Edit set count, rep range/unit, notes, load increment, optional state, and alternatives.
- Load increments respect metric/imperial input and are stored in kilograms.
- Create future-only effective-dated nutrition targets and close the prior interval.
- Edit care recurrence, reminders, task order, generic role/active, instructions, and archive state.
- Plan writes retain historical snapshots and trigger reconciliation.

### Progress

- Raw body-weight observations and a seven-calendar-day average.
- Same-day weight readings are averaged before the rolling average; at least two distinct days are required.
- Waist observations and an optional seven-day due indicator.
- Calories with historical target range and protein with minimum target.
- Explicit exercise selection, total volume, highest completed weight, and best repetitions at each weight.
- Workout, nutrition, and care streak history plus adherence chart.
- Load suggestions support Use, Edit, and Dismiss; accepted weight becomes the prescription working weight.
- Metric/imperial input, display, chart, summary, and accessibility values are consistent.
- No estimated one-repetition maximum is calculated.
- Milestones are generated idempotently for workout thresholds, category-streak records, exercise bests, and consecutive in-range nutrition days.
- Progress presents one calm, persistently acknowledged milestone at a time.

### Settings, reset, and release assets

- Selected appearance is applied at the app shell.
- Units affect workout, plan, History, post-workout, and Progress inputs/displays.
- Saved reminder changes reschedule notifications.
- Domain Day cutoff changes show old/new times, the current attribution effect, and require confirmation.
- Canonical settings are used throughout the app.
- Reset reseeds immediately and cancels Momentum reminders.
- Preview/local development stores explicitly disable CloudKit.
- A 1024×1024 App Store icon is included in the asset catalog.
- New History sources and tests are included in the generated Xcode project.
- Cloud account changes and foreground activation refresh a truthful account-availability state without claiming an unobserved successful sync.
- Material time-zone changes are detected separately, require accept/defer confirmation, and leave logging available while reconciliation is deferred.
- Duplicate unfinished Workout Sessions have an explicit choose-one resolver; nonselected sessions are soft-deleted without merging logs.
- OSLog signposts cover Today aggregation, reconciliation, heatmap computation, and Cloud account-state processing.

## Remaining implementation gaps

### GAP-R1 — CloudKit import evidence, schema promotion, and production verification

**Priority:** P0 before release
**Current state:** Production uses a private CloudKit-backed SwiftData configuration and has the required entitlements. Account availability is refreshed truthfully, duplicate local/imported singletons and occurrences are repaired deterministically, and duplicate active sessions have user-resolution UI. End-to-end import/export behavior is not certified.

Required work:

- Add an import/export completion signal before ever transitioning from `Syncing` to `Synced recently`; account availability alone intentionally remains `Syncing`.
- Initialize and inspect the development schema, then promote the intended production schema.
- Verify create/edit/delete sync between two signed installations using the same Apple ID.
- Verify offline writes followed by reconnect, including reset deletions.
- Add deterministic repair/reporting for impossible imported cycle orders and other multi-record conflicts.
- Add migration coverage from every schema shipped to users.

Acceptance evidence:

- two-device test log;
- offline/reconnect test log;
- CloudKit schema screenshots or exported schema record;
- automated duplicate-singleton/occurrence/event and migration tests.

### GAP-R2 — Enrich time-zone attribution preview

**Priority:** P2
**Current state:** Material time-zone changes are persisted, distinguished from ordinary activation, and require accept/defer confirmation. Reconciliation remains deferred after Later while logging stays available.

Required work:

- Enrich the confirmation with concrete recent Domain Days whose attribution would change, rather than only old/new time-zone names.
- Add explicit eastbound/westbound and daylight-saving acceptance fixtures beyond the current decision-policy tests.

### GAP-R3 — Physical performance evidence

**Priority:** P2
**Current state:** Views use lazy containers and the required diagnostic signposts are present. Physical measurements are absent.

Required work:

- Profile Today, Workout Session, and 52-week History scrolling on the physical target class.
- Confirm launch, memory, and scrolling budgets with a production-sized fixture.

## Verification gaps rather than code gaps

These tasks require external infrastructure, a physical device, or manual inspection:

- Assign/confirm the Apple Development Team for archive signing; `project.yml` intentionally does not hard-code a developer account.
- Validate notification delivery/actions while foregrounded, backgrounded, and terminated.
- Run VoiceOver, Accessibility Inspector, accessibility Dynamic Type sizes, Increased Contrast, Reduce Motion, Reduce Transparency, grayscale, and common color-vision simulations.
- Verify light/dark UI and representative empty/error/offline states visually.
- Open all five CSV exports in Apple Numbers and verify Unicode and columns.
- Capture App Store screenshots and complete App Store Connect metadata/privacy answers.

## Automated verification at this checkpoint

- `swift test`: **53 passed, 0 failed**.
- iPhone 17 Pro Max simulator on iOS 26.4: **52 passed, 0 failed** across app unit and UI tests.
- Generic iOS Simulator app build: passed.
- `git diff --check`: passed.

The automated suite now also covers History correction transactions, workout timestamp previews, milestone thresholds/idempotency/correction, Cloud account-state policy, time-zone change decisions, persistence store-mode selection, and duplicate-session resolution.

## Recommended next handoff order

1. Complete GAP-R1 and capture real CloudKit evidence.
2. Enrich and fixture-test the time-zone attribution preview in GAP-R2.
3. Capture physical performance evidence and run the full manual/device release matrix.
4. Archive, sign, and perform the final App Store preflight.
