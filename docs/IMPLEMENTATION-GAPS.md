# Momentum v1 Implementation Gaps and Luna Handoff

## 1. Purpose

This document is the execution handoff for completing Momentum v1 from the
`agent/continue-momentum` branch. It records:

- the exact branch and commit audited;
- what is already implemented and should be preserved;
- defects in existing implementations that must be fixed;
- product areas that still need to be implemented;
- required behavior, dependencies, and acceptance tests;
- external and physical-device verification that cannot be replaced by a
  simulator build.

The intended reader is a Luna implementation agent. This is not a replacement
for the normative product and technical specifications. If this document and a
normative source disagree, follow the normative source and update this handoff.

## 2. Audited baseline

- Repository: `prathams96/momentum`
- Branch: `agent/continue-momentum`
- Audited commit: `272371f5f90a4586bb02826b0fbdd1ae4b5ec4f7`
- Commit title: `feat: build momentum core vertical slices`
- Audit date: 2026-08-02
- Local worktree at audit: clean and equal to the GitHub branch SHA
- Comparison branch: `origin/master`
- Branch delta from `origin/master`: 46 files, 7,087 insertions, 312 deletions

Do not use the earlier `8b8c5cc`/`master` audit as current state. The target
branch now contains the schema, domain engines, logging vertical slices,
Settings, export, notifications infrastructure, and expanded tests that were
previously described as missing.

## 3. Normative source order

Read and apply repository documents in this order:

1. `PRODUCT.md`
2. `CONTEXT.md`
3. `docs/adr/0001-use-a-continuous-recovery-driven-workout-cycle.md`
4. `docs/adr/0002-use-swiftdata-with-private-cloudkit-sync.md`
5. `docs/PRODUCT-SPEC.md`
6. `docs/TECHNICAL-SPEC.md`
7. `DESIGN.md`
8. `UL_4_Day_Workout_Plan.md` for seed workout content only
9. `Skincare.md` for seed care content only

Precedence:

- ADRs govern architecture and workout scheduling.
- `CONTEXT.md` governs domain terminology.
- `docs/PRODUCT-SPEC.md` governs user-visible behavior.
- `docs/TECHNICAL-SPEC.md` governs models, algorithms, integration, and
  verification.
- `DESIGN.md` governs visual and interaction behavior.
- Workout and skincare source files provide seed content only where newer
  specifications do not override them.

Do not silently invent a product decision when the sources genuinely conflict.
Record the conflict and request a decision.

## 4. Nonnegotiable domain rules

- The Workout Cycle is continuous: Upper A → Lower A → Upper B → Lower B.
- The cycle is not anchored to weekdays and never resets on Monday.
- Recovery is anchored to the actual Workout Session completion Domain Day.
- Missed and Skipped Workouts do not advance the Workout Cycle.
- The same Due Workout remains due until finished.
- The app never creates catch-up sessions or recommends doubling up.
- Start Early is allowed after factual confirmation of remaining recovery.
- Finish Workout records a completed session and advances the cycle.
- There is no session-level partial-workout status.
- Individual exercises and sets may be skipped.
- Routine and target edits affect future facts only; historical snapshots remain
  understandable and stable.
- Food is manually named and manually assigned calories and protein.
- Care uses generic product roles or active ingredients, never product brands.
- Waiting periods are written guidance, not timers.
- Adapalene frequency never changes automatically.
- Recovery contributes no adherence obligation.
- Notifications are local; there is no app backend, analytics SDK,
  authentication SDK, or third-party runtime dependency.
- Data is local-first, private, CloudKit-compatible, and exportable.

## 5. Verification performed on the audited commit

The branch is technically healthy but not product-complete.

- `swift test`: 53 tests passed.
- Xcode application unit tests: 11 tests passed.
- Xcode UI tests: 1 test passed.
- iOS Simulator Debug build: succeeded.
- `git diff --check origin/master...HEAD`: passed.
- No source reference to a prohibited product brand, analytics SDK, or network
  client was found in the scoped search.

The UI test covers launch and onboarding only. Passing tests should not be read
as evidence that the missing History, notification, correction, Progress, or
CloudKit scenarios work.

## 6. Current implementation inventory

### 6.1 Implemented foundations to preserve

The target branch now contains:

- an iOS 26 SwiftUI application shell with four tab items and independent
  `NavigationStack` containers;
- iPhone-only project configuration for `com.pratham.momentum`;
- private CloudKit model configuration and CloudKit/remote-notification
  entitlements;
- a complete registered 20-record SwiftData schema:
  - `AppSettingsRecord`
  - `NutritionTargetRecord`
  - `WorkoutTemplateRecord`
  - `CycleAnchorRecord`
  - `ExercisePrescriptionRecord`
  - `ExerciseAlternativeRecord`
  - `WorkoutSessionRecord`
  - `ExerciseLogRecord`
  - `SetLogRecord`
  - `WorkoutDayEventRecord`
  - `LoadSuggestionRecord`
  - `FoodPresetRecord`
  - `FoodEntryRecord`
  - `NutritionDayRecord`
  - `CareRoutineTemplateRecord`
  - `CareTaskTemplateRecord`
  - `CareOccurrenceRecord`
  - `CareTaskCompletionRecord`
  - `BodyMeasurementRecord`
  - `MilestoneRecord`;
- versioned seed installation through `SeedData.currentVersion == 3`;
- pure, tested domain implementations for:
  - Domain Day calculation;
  - workout scheduling;
  - care recurrence;
  - nutrition calculation;
  - progression suggestions;
  - adherence scores and category streaks;
  - RFC 4180 CSV encoding;
- expanded onboarding with cycle selection, due-day choice, editable nutrition
  targets, care reminder times, notification explanation, and iCloud state;
- Today integration with `ScheduleEngine`, including due, overdue, recovery,
  active-session, and repair states;
- workout session snapshot creation and working-set logging;
- food create/edit form, recent presets, and favorites;
- care occurrence/task completion UI with conditional choices;
- a typed Settings screen with reminder, cutoff, unit, appearance, export, and
  destructive reset controls;
- five CSV export files and automated encoding/export tests;
- local notification categories and a scheduler API;
- privacy manifest and named color assets.

These are meaningful vertical slices. Complete them rather than replacing them
with parallel implementations.

### 6.2 Top-level product status

| Product area | Current status | v1 consequence |
|---|---|---|
| Onboarding | Mostly implemented | Needs persistence/lifecycle integration and device verification |
| Today workout state | Functional vertical slice | Needs confirmation, notification, history, and performance integration |
| Workout Session | Partial | Core logging works; several required session behaviors are absent |
| Nutrition | Partial | Entry form works; daily status/finalization/history operations are absent |
| Care | Partial | Scheduled routine completion works; post-workout care and undo are absent |
| History | Placeholder | No correction or chronological historical UI |
| Plans | Placeholder | No plan editing UI |
| Progress | Placeholder | No measurements, charts, or milestone UI |
| Settings | Partial | Values persist, but several settings have no runtime effect |
| Notifications | Infrastructure only | No reminders are actually derived, reconciled, or acted upon |
| CSV export | Implemented and unit-tested | Apple Numbers/manual export verification remains |
| CloudKit | Configured only | Conflict repair and two-installation sync are unverified |
| Release assets | Incomplete | No app icon image; localization catalog is empty; signing team is unset |

## 7. Gap matrix

Priority meanings:

- P0: blocks primary product behavior or reliable data.
- P1: required for v1 acceptance but can follow core logging correctness.
- P2: release verification, polish, or maintainability work that remains
  mandatory before distribution.

| ID | Area | Type | Status | Priority |
|---|---|---|---|---|
| GAP-001 | Simulator persistence and bootstrap safety | Fix | Incorrect | P0 |
| GAP-002 | Daily reconciliation and lifecycle triggers | Fix/complete | Partial | P0 |
| GAP-003 | Notification derivation, scheduling, and actions | Implement | Infrastructure only | P0 |
| GAP-004 | Today nutrition and consistency aggregation | Implement | Partial | P0 |
| GAP-005 | Workout Session completion behaviors | Fix/complete | Partial | P0 |
| GAP-006 | Nutrition lifecycle and entry management | Implement | Partial | P0 |
| GAP-007 | Care completion, post-workout care, and undo | Implement | Partial | P0 |
| GAP-008 | History and correction | Implement | Missing | P0 |
| GAP-009 | Adherence heatmap and streak presentation | Implement | Engine only | P1 |
| GAP-010 | Measurements, Progress, and milestones | Implement | Models only | P1 |
| GAP-011 | Plans editors | Implement | Missing | P1 |
| GAP-012 | Settings runtime behavior and reset recovery | Fix/complete | Partial | P1 |
| GAP-013 | CloudKit conflicts, migrations, and sync evidence | Implement/verify | Configuration only | P1 |
| GAP-014 | Diagnostics, accessibility, localization, and performance | Implement/verify | Partial | P2 |
| GAP-015 | Release assets, signing, and distribution evidence | Implement/verify | Incomplete | P2 |
| GAP-016 | Automated and manual acceptance coverage | Implement/verify | Partial | P1 |

## 8. Detailed gaps

### GAP-001 — Fix simulator persistence and bootstrap safety

#### Current condition

`Momentum/MomentumApp.swift` treats every Simulator execution as a preview run.
`PersistenceBootstrap` therefore calls `ModelContainerFactory.makePreview()`,
whose configuration is stored in memory only.

Consequences:

- simulator data disappears after app termination;
- simulator testing cannot verify offline relaunch behavior;
- the production local/CloudKit container path is never exercised on Simulator;
- the current UI test passes partly because every launch begins from a newly
  seeded database;
- the Product Spec requirement that primary logging survive termination is not
  testable in the normal development environment.

#### Required fix

- Use the in-memory store only for XCTest, explicit preview launches, or an
  explicit `-usePreviewStore` argument.
- Give ordinary Simulator launches a disk-backed store.
- If CloudKit cannot be used in a specific simulator/test environment, create an
  explicit disk-backed local development configuration rather than silently
  selecting an in-memory container.
- Keep production configuration private-CloudKit-backed on signed devices.
- Make the selected store mode visible to tests through dependency injection or
  a narrow bootstrap seam; do not infer behavior throughout feature code with
  repeated `targetEnvironment(simulator)` branches.
- Ensure a production-container failure offers Retry and diagnostics without
  creating or overwriting a second store.

#### Required tests

- Create workout, food, and care facts; terminate and relaunch; verify they
  remain.
- Verify `-usePreviewStore` is isolated and reset between test executions.
- Verify ordinary simulator launch does not use `isStoredInMemoryOnly`.
- Verify bootstrap failure does not replace existing local data.

#### Exit criteria

Primary logging persists through simulator termination and physical-device
termination, and automated UI tests explicitly opt into isolated fixtures.

### GAP-002 — Complete DailyReconciler and lifecycle integration

#### Current condition

`Momentum/Core/Persistence/DailyReconciler.swift` currently:

- selects the newest settings record;
- computes today and yesterday using the cutoff;
- marks yesterday's pending care occurrences missed;
- rolls eligible missed care forward;
- creates today's care occurrences and task snapshots;
- uses the versioned `CareScheduleEngine` where possible;
- saves the context.

It does not:

- create a `WorkoutDayEventRecord` when a Due Workout expires;
- distinguish a prior explicit skip from a missed workout;
- reconcile a bounded historical/future occurrence window;
- repair duplicate logical occurrences or events;
- rebuild facts after historical edits;
- invoke notification reconciliation;
- surface invalid recurrence as an editor repair state;
- run from the required lifecycle and mutation triggers.

Today invokes the reconciler only from `.task(id: currentDomainDay)`. There is no
scene-phase handling, significant-time-change observer, CloudKit-import hook, or
post-edit integration.

#### Required implementation

Create one idempotent reconciliation entry point that:

1. resolves the canonical settings and Cycle Anchor;
2. computes the current Domain Day with injected Calendar, time zone, and clock;
3. reconciles care occurrences within a documented bounded window;
4. expires nonrolling care and rolls hair care exactly once;
5. records one missed Workout Day Event for each elapsed Due opportunity without
   a completion or explicit skip;
6. repairs duplicate events/occurrences using deterministic composite keys;
7. rebuilds affected schedule/adherence facts after historical mutation;
8. derives desired reminders and calls `NotificationScheduler.reconcile`;
9. records privacy-safe diagnostics for repairs and scheduling failures.

Invoke it:

- after onboarding is committed;
- when the app becomes active;
- on `UIApplication.significantTimeChangeNotification`;
- after cutoff, plan, routine, or reminder edits;
- after workout, nutrition, or care completion/skip/undo;
- after History corrections;
- after CloudKit-imported changes become visible.

Do not implement each trigger with different business logic. They should all call
the same idempotent service.

#### Required tests

- repeated reconciliation produces no duplicates;
- a missed Due Workout produces exactly one event and does not advance the cycle;
- an explicit skip prevents a missed event and retains the same Due Workout;
- rolling hair care happens once and continues from actual completion;
- invalid recurrence affects only its routine and produces a repair state;
- cutoff, daylight-saving, and time-zone transitions use Calendar arithmetic;
- historical deletion/edit rebuilds all affected facts;
- desired pending notification identifiers equal the current plan and facts.

### GAP-003 — Implement notification derivation, reconciliation, and actions

#### Current condition

`NotificationScheduler` defines:

- `WORKOUT_DUE`, `CARE_DUE`, and `EVENING_CHECKIN` categories;
- Start, Done, Open Today, Remind 30 Minutes, and Skip Today actions;
- category configuration;
- permission request/status;
- pending-request replacement and cancellation.

No application feature constructs the required `ScheduledReminder` set or calls
`reconcile`. No `UNUserNotificationCenterDelegate` handles notification
responses. Consequently no product reminder is actually scheduled and action
buttons do not mutate the model.

#### Required implementation

- Create a pure reminder derivation layer from the current Due Workout,
  `CareOccurrenceRecord` facts, `NutritionDayRecord`, settings, and current
  Domain Day.
- Schedule only the next actionable workout reminder.
- Use stable identifiers derived from kind plus stable record ID/Domain Day.
- Use one-shot reminders for variable care and hair-care occurrences.
- Coalesce unfinished nutrition and night care at the same time into one Evening
  Check-in.
- Cancel obsolete pending requests immediately after every relevant mutation.
- Install one notification delegate at app startup.
- Route actions through the main `ModelContext`, then reconcile and refresh UI.
- Implement:
  - Start Workout → foreground and open/start the correct workout;
  - Remind in 30 Minutes → replace the actionable reminder idempotently;
  - Skip Today for workout → create one skipped event without advancing cycle;
  - Done for care → complete the whole occurrence idempotently;
  - Skip Today for care → mark the occurrence skipped;
  - Open Today → select the Today tab and appropriate sheet when applicable.
- Preserve full app use when authorization is denied.
- Surface scheduling failure as status in Settings without rolling back a valid
  plan or completion.

#### Required tests

- category/action definitions;
- exact pending-request reconciliation and stale cancellation;
- coalesced and noncoalesced evening cases;
- every action, including repeated delivery/tap idempotency;
- plan edit, completion, skip, foreground, and time-zone rescheduling;
- denied authorization and scheduling failure behavior.

Physical-device notification verification remains mandatory.

### GAP-004 — Implement complete Today aggregation

#### Current condition

Today correctly uses `ScheduleEngine` for workout state and renders due, overdue,
recovery, active-session, and repair states. It also opens food and care sheets.

The nutrition row is only a Log Food action. Today does not query food entries,
nutrition targets, or nutrition-day finalization. It therefore cannot show:

- consumed calories against the target range;
- protein against the minimum;
- open versus finalized state;
- Finish Logging Today or Reopen;
- entry list/edit operations.

The consistency section renders 16 horizontal rectangles based only on completed
workouts. It is not the required 7-row-by-16-week scored heatmap and has no
category streaks.

Today also performs schedule mapping, filtering, sorting, and consistency
calculation in View computed properties. This conflicts with the technical
requirement to keep aggregation outside View bodies and fetch range-relevant
history.

#### Required implementation

- Create a narrow Today aggregation store/service with injected clock, Calendar,
  and pure engines.
- Return a stable Today view state containing:
  - current Domain Day and formatted date;
  - Due/Recovery/Active/Repair workout state;
  - nutrition totals, target snapshot, range evaluation, and finalization state;
  - ordered due care occurrences;
  - 16-week adherence cells and current category streaks.
- Fetch only records necessary for today and the displayed heatmap range where
  practical.
- Make the content order match Product Spec §6.
- Add factual Start Early confirmation that states remaining recovery and never
  blocks the action.
- Use a full-screen cover for an active Workout Session.
- Replace `settings.first` with deterministic newest-settings resolution and
  duplicate repair.
- Provide actionable empty and repair states.

#### Required tests

- Today aggregation for fresh, due, overdue, recovery, active, and repair states;
- open/finalized nutrition totals and target boundaries;
- ordered care occurrences and generated post-workout care;
- 16-week heatmap facts and streak summaries;
- save/reconciliation failures retain user context;
- performance fixture with at least 52 weeks of history.

### GAP-005 — Complete Workout Session behavior

#### Current condition

Implemented:

- one-open-session protection;
- session, exercise, and working-set snapshots;
- weight, repetitions, RIR, set status, and notes;
- resuming an unfinished session;
- factual confirmation when unfinished sets remain;
- skipped unfinished sets on Finish Workout;
- completed-session timestamps and completion Domain Day;
- progression suggestion creation when all required sets reach the rep maximum;
- retry behavior for save failure.

Missing or incorrect:

- Today presents the session in a sheet, not an immersive full-screen cover;
- previous-session values are not visible or copyable;
- configured exercise alternatives cannot be selected;
- there is no explicit exercise-level Skip action;
- generated progression suggestions have no accept/edit/dismiss UI;
- accepted suggestions are not applied to future prescription state;
- Finish Workout does not ask `Heavy sweating?` or `Going outdoors again?`;
- Finish Workout does not offer optional weight entry;
- session completion does not reconcile reminders;
- dense set rows are likely to clip at accessibility Dynamic Type sizes;
- there are no tests for finish behavior or recovery transition through
  persistence/UI.

#### Required implementation

- Present active sessions with `fullScreenCover`.
- Show prior matching exercise/set values from the latest nondeleted historical
  session, with a Copy action that modifies only the current draft.
- Allow swapping to a seeded/configured `ExerciseAlternativeRecord`; snapshot the
  chosen name without changing past sessions or templates.
- Add exercise-level Skip while keeping individual set Skip.
- After finish, present pending Load Suggestions with Accept, Edit, and Dismiss.
  Accept updates the applicable future prescription only; all resolutions record
  status and `resolvedAt`.
- Add the post-workout care questions and generated Today occurrences.
- Offer optional weight measurement entry with `sourceRaw == postWorkout`.
- Commit the completed session and its dependent records as one coherent
  operation, then reconcile schedule and reminders.
- Preserve entered set values across recoverable save errors.
- Reflow set rows vertically when Dynamic Type requires it and provide one logical
  VoiceOver announcement per set.

#### Required tests

- start, resume, close/reopen, finish, unfinished-set confirmation;
- exercise/set skipping with no session-level partial state;
- previous values and Copy;
- alternative snapshot behavior;
- progression suggestion accept/edit/dismiss;
- 0/1/0/2 cycle transition after persisted completions;
- early completion anchoring;
- post-workout care and weight paths;
- termination during an open session and recovery after relaunch.

### GAP-006 — Complete nutrition lifecycle and entry management

#### Current condition

`FoodEntrySheet` supports validated create/edit, serving multiplier totals,
favorites, and recent presets. However, only creation is reachable from Today.
There is no food-entry list or caller that supplies `existingEntryID`.

Missing:

- Today totals and target visualization;
- duplicate entry;
- swipe-to-delete with soft deletion;
- reachable editing after save;
- explicit Nutrition Day creation;
- Finish Logging Today;
- Reopen after finalization;
- target snapshots at finalization;
- historical backdating/edit/delete UI;
- nutrition reminder derivation and coalescing;
- empty state for Log First Food.

#### Required implementation

- Provide a Today nutrition section listing current entries and totals.
- Route an entry to `FoodEntrySheet(existingEntryID:)` for editing.
- Implement Duplicate and swipe-to-delete; use `deletedAt` so CloudKit and export
  retain historical truth.
- Recompute and persist totals whenever base values or multiplier change.
- Create or resolve one logical `NutritionDayRecord` per Domain Day.
- Finish Logging Today must snapshot the effective target and set `finalizedAt`.
- Reopen clears finalization without deleting entries.
- Edits after finalization remain allowed and recompute totals/adherence.
- Use effective-dated targets; plan edits must not rewrite historical snapshots.
- Generate unfinished-nutrition reminders and coalesce with night care.

#### Required tests

- create, favorite, recent reuse, edit, duplicate, and delete;
- multiplier and decimal behavior;
- finalization, reopen, and edits after finalization;
- target effective-date boundaries and snapshots;
- backdated entries across cutoff/time-zone cases;
- reminder coalescing;
- export of active and deleted entries.

### GAP-007 — Complete care, post-workout generation, and undo

#### Current condition

Scheduled care occurrences and snapshotted tasks are created. The care sheet
supports required tasks, conditional cleanse selection, individual task state,
whole-routine completion, and save retry.

Missing:

- explicit occurrence Skip Today;
- undo of whole-routine completion from Today and History;
- notification Done/Skip/Snooze integration;
- generated post-workout Wash Face and Reapply Sunscreen routines;
- schedule/editor repair routing for unsupported recurrence payloads;
- post-completion advancement of alternating hair recurrence;
- lifecycle reminder refresh after completion;
- History editing and deletion of care facts.

#### Required implementation

- Add whole-occurrence Skip Today with factual copy and adherence impact.
- Add a reversible completion banner/action on Today and History.
- Make whole-routine Done idempotent regardless of UI or notification origin.
- Generate post-workout care from the specified questions, using snapshots and
  the workout completion Domain Day.
- Include generated routines in Today, History, adherence, and export.
- Continue the hair-care 3/4 cadence from actual completion after a roll.
- Route invalid/unsupported recurrence to the Plans editor repair state without
  disabling unrelated care.
- Reconcile notifications after every mutation.

#### Required tests

- all weekday routines;
- conditional choice behavior;
- alternating cadence and rolled completion;
- whole-routine complete/undo/skip;
- repeated notification Done action;
- post-workout care paths;
- historical correction and export.

### GAP-008 — Implement History and correction flows

#### Current condition

History is a `ContentUnavailableView` placeholder. There is no calendar,
category filter, chronological day detail, historical editor, destructive
preview, or correction transaction.

This blocks Product Acceptance Criterion 6 and prevents the user from correcting
workout, food, care, or measurement history.

#### Required implementation

History must provide:

- an all-category heatmap;
- workout, nutrition, and care filters;
- calendar/month navigation and horizontal access to older heatmap history;
- chronological details for the selected Domain Day;
- backdated create, edit, duplicate where applicable, and delete;
- destructive confirmation explaining downstream effects;
- simple same-session undo where practical.

Completed Workout Session correction requires a dedicated preview transaction:

1. derive the current next workout and due date;
2. apply the proposed edit/delete to an in-memory fact set;
3. derive the resulting next workout and due date;
4. show before/after results to the user;
5. commit only after confirmation;
6. rebuild Workout Day Events, care/nutrition-derived state, adherence, and
   notifications;
7. preserve snapshots and soft-deletion semantics.

Never mutate live records merely to calculate a preview.

#### Required tests

- range fetch, filtering, and Domain Day detail ordering;
- backdated create/edit/delete in each category;
- workout before/after preview;
- deleting latest and nonlatest completed sessions;
- edited completion timestamp/cutoff attribution;
- next workout/due date recomputation;
- streak, heatmap, totals, and notification recomputation;
- destructive cancel leaves all records unchanged.

### GAP-009 — Implement adherence heatmap and streak presentation

#### Current condition

`AdherenceEngine` has useful pure coverage for equal activity weighting,
no-obligation days, workout recovery neutrality, nutrition finalization streaks,
care streaks, rolling hair behavior, and long histories.

The engine is not connected to persisted facts or UI. Today's current
consistency row only checks whether a workout finished on each of 16 days.

#### Required implementation

- Build a mapper from persisted schedule, nutrition, and care facts to pure
  `AdherenceActivity`/streak inputs.
- Include Due Workout, nutrition finalization, morning care, night care, due hair
  care, and generated post-workout care with equal weight.
- Treat Recovery and days with no due activities as no-obligation, not 0%.
- Render 16 weeks initially as weekdays by week columns.
- Support horizontal access to older history.
- Use the five required intensity levels.
- Use shape/symbol/numeric information so color is not the sole signal.
- Each cell must expose Domain Day, score, due count, completed count, and category
  summary to VoiceOver.
- Show current Workout, Nutrition Logging, and Personal Care streaks.
- Recompute rather than persist authoritative adherence values.

#### Required tests

- persistence-to-fact mapping;
- all score thresholds;
- skipped/missed workouts and recovery neutrality;
- finalized/reopened nutrition;
- rolled hair care and generated post-workout care;
- at least 18 months of fixture history;
- History corrections immediately changing cells and streaks.

### GAP-010 — Implement measurements, Progress, and milestones

#### Current condition

`BodyMeasurementRecord` and `MilestoneRecord` exist and round-trip in a model
test, but no production feature creates or displays them. Progress is a
placeholder. The project contains no Swift Charts usage.

#### Required implementation

Measurements:

- manually add/edit/delete Weight and Waist measurements;
- offer Weight after Finish Workout without making it mandatory;
- mark Waist as due after seven days without sending a notification;
- use one Domain Day calculation and snapshot absolute timestamp;
- support history correction and CSV export.

Progress:

- raw weight observations plus seven-day average when sufficient data exists;
- waist observations;
- daily calories with target range;
- daily protein with minimum;
- exercise total volume over time;
- highest completed weight and best repetitions at each weight;
- adherence and category-streak history;
- explicit exercise selection;
- accessible textual summaries and useful empty states.

Milestones:

- 10, 25, and 50 completed workouts;
- new category-streak records;
- exercise bests;
- consecutive days inside nutrition target range;
- idempotent generation and restrained acknowledgement.

Do not compute one-repetition maximums or label weight changes as success or
failure.

#### Required tests

- Domain Day attribution and corrections;
- seven-day average with missing/multiple observations;
- volume and exercise-best aggregation;
- target changes and historical snapshots;
- milestone threshold/idempotency;
- chart empty/sparse/large-data states and accessibility summaries.

### GAP-011 — Implement Plans editors

#### Current condition

Plans is a placeholder. Seed templates can be read by other features but cannot
be edited through the app.

#### Required implementation

Workout plans:

- reorder active Workout Templates with contiguous indices;
- keep at least one active workout;
- edit focus and recovery days after each workout;
- add, archive/remove, reorder, and edit prescriptions;
- edit set count, rep range, RIR guidance, notes, load increment, and optional
  state;
- add, remove, reorder, and choose alternatives;
- preview schedule effect where a current/future due state changes.

Nutrition plans:

- create a new effective-dated target instead of rewriting historical targets;
- edit display target, green range, and protein minimum;
- validate range ordering and positive values.

Care plans:

- edit recurrence, task order, generic product role/active, instructions, and
  reminder time;
- edit alternating state safely;
- surface and repair unsupported recurrence payloads;
- never seed or display a product brand;
- never progress adapalene automatically.

After a successful plan edit, reconcile occurrences, schedule, and reminders.
Historical snapshots must remain unchanged.

#### Required tests

- reordered cycle and removed-template schedule behavior;
- invalid sequence/order rejection;
- future-only workout, nutrition, and care edits;
- exercise alternative lifecycle;
- recurrence repair;
- plan save failure retains drafts;
- notification reconciliation after plan edits.

### GAP-012 — Complete Settings runtime behavior and reset recovery

#### Current condition

Settings persists cutoff, units, appearance, workout/nutrition reminder times,
per-routine reminder times, and provides CSV sharing and destructive reset.

Known issues:

- appearance is stored but never applied with `preferredColorScheme`;
- unit selection is stored but logging/display continues to hard-code kilograms;
- reminder edits do not reschedule notifications;
- iCloud status fields are not updated by a sync observer, so the displayed state
  is not trustworthy;
- changing the cutoff has no preview/confirmation of recent Domain Day effects;
- time-zone attribution confirmation is absent;
- duplicate singleton settings are selected inconsistently (`settings.first` in
  AppShell/Today versus newest `updatedAt` elsewhere);
- Reset All Data removes seed plans and settings, but `SeedData.install` runs only
  during app bootstrap. The running app can land in empty onboarding and cannot
  complete normally until relaunched.

#### Required implementation

- Resolve, merge, and tombstone duplicate settings deterministically.
- Expose one canonical settings dependency to features.
- Apply appearance at the app shell/root.
- Either fully implement supported unit conversion/input or keep v1 explicitly
  metric and remove a misleading inactive selector. Follow the normative product
  decision rather than leaving a no-op control.
- Reconcile reminders after a saved reminder change.
- Track truthful states: Syncing, Synced recently, iCloud unavailable, Local only.
- Confirm before cutoff or time-zone change alters recent attribution, showing
  concrete affected days where practical.
- After Reset All Data, cancel reminders and either reseed immediately into a
  valid first-launch state or intentionally terminate/rebootstrap with clear UX.
- Ensure reset deletions are allowed to synchronize through CloudKit.

#### Required tests

- appearance and unit behavior;
- canonical duplicate settings repair;
- cutoff/time-zone preview and cancel;
- notification rescheduling after Settings save;
- accurate sync-status transitions;
- reset followed by immediately completable onboarding;
- reset/reconnect CloudKit deletion behavior.

### GAP-013 — Complete CloudKit conflict handling and sync verification

#### Current condition

The schema avoids unique constraints and required relationships, and production
uses a private CloudKit ModelConfiguration. Entitlements and remote-notification
background mode exist.

Not implemented or evidenced:

- development schema initialization/inspection;
- production schema promotion;
- two-installation same-Apple-ID verification;
- offline create/edit/delete followed by reconnect;
- latest-`updatedAt` merge rules;
- deterministic singleton/occurrence/event repair;
- impossible cycle-order repair;
- user resolution for duplicate open sessions;
- migration tests from released schema versions;
- truthful sync-status observation.

Today's duplicate-open-session repair screen instructs the user to resume or
close one, but the UI does not let the user select and resolve each session.

#### Required implementation

- Centralize duplicate and conflict repair policies.
- Use soft deletion where history must synchronize and remain exportable.
- Keep schedule and adherence derived from repaired facts.
- Provide a usable Needs Repair flow for duplicate open sessions and invalid
  cycle order; never silently discard a session.
- Observe imports/sync changes and trigger reconciliation without promising
  immediate cloud delivery.
- Add versioned migration planning/tests before promoting a production schema.

#### Required evidence

- two signed installations on the same Apple ID;
- offline create/edit/delete on both, then reconnect;
- concurrent Settings edits;
- duplicate open sessions and occurrence/event repair;
- deletion propagation;
- local availability during iCloud outage;
- CloudKit schema inspection and promotion record.

### GAP-014 — Diagnostics, accessibility, localization, and performance

#### Current condition

The app uses system text styles and several accessibility labels, but no complete
audit exists. `Localizable.xcstrings` contains no strings. No OSLog signposts or
Swift Charts are present. Today and Workout Session perform broad queries and
substantial filtering/sorting in View code.

#### Required implementation

Diagnostics:

- typed errors at persistence, notification, export, and correction boundaries;
- privacy-safe Logger categories;
- signposts around Today aggregation, reconciliation, heatmap computation, and
  CloudKit import processing;
- diagnostics export on model-container failure;
- never log food names, notes, measurements, or care state.

Accessibility and visual behavior:

- minimum 44-point hit targets;
- logical set-row announcements with weight, reps, RIR, and status;
- Dynamic Type reflow for dense rows;
- complete heatmap cell descriptions;
- symbols/text in addition to color;
- Reduce Motion and Reduce Transparency behavior;
- Increased Contrast and grayscale/color-blind verification;
- light/dark verification for loaded, empty, error, overdue, and recovery states.

Localization:

- extract user-visible strings into `Localizable.xcstrings`;
- keep v1 English while using localization-ready APIs;
- do not concatenate fragments to construct sentences;
- test date, number, decimal, and CSV formatting independently.

Performance:

- preaggregate Today/History/Progress outside View bodies;
- use range-limited fetches and stable IDs;
- use lazy grids/stacks for heatmaps and history;
- avoid full-session redraw when one set changes;
- profile Today, Workout Session, and 52-week heatmap on the physical target
  device.

### GAP-015 — Complete assets, signing, and distribution readiness

#### Current condition

- `AppIcon.appiconset` contains only `Contents.json`; no 1024×1024 icon file is
  present.
- The developer team setting is blank.
- The privacy manifest exists but has not been validated against the final
  binary/API use.
- App Store/distribution archive, CloudKit production schema, and signed-device
  behavior have not been verified.

#### Required implementation and evidence

- add the final 1024×1024 app icon and validate asset compilation;
- configure automatic signing with the Routine Owner's paid team;
- validate bundle identifier, iCloud container, entitlements, and provisioning;
- audit the final privacy manifest;
- initialize and inspect the CloudKit development schema;
- produce a signed archive and install it on the target iPhone;
- record the exact version/build and verification device/OS;
- verify no third-party SDK, analytics, prohibited network client, brand, or v1
  non-goal appears in the final source or binary.

### GAP-016 — Expand automated and manual acceptance coverage

#### Current condition

Pure engines have useful coverage. Application tests cover schema round trips,
seed idempotency, workout start snapshots, second-session rejection, Settings
draft/reset, and CSV encoding/export. The only UI test launches, completes basic
onboarding, and finds the tab bar.

Missing coverage includes most Technical Spec §20 scenarios.

#### Required automated suites

Unit/domain:

- complete schedule miss/skip/edit/delete/cutoff/time-zone matrix;
- reminder derivation and notification actions;
- persistence-to-adherence mapping;
- post-workout care;
- duplicate repair and recurrence repair;
- seed fixture snapshots against both source documents;
- measurement/chart aggregations and milestones.

Persistence/integration:

- daily reconciliation idempotency;
- session finish and progression resolution;
- nutrition finalization/reopen;
- History correction transactions;
- reset/reseed;
- migrations;
- disk-backed termination/relaunch.

UI:

- notification denial onboarding;
- start/finish Upper A and verify Lower A;
- miss, skip, snooze, and Start Early;
- food favorite/reuse/edit/duplicate/delete;
- finalize and reopen nutrition;
- conditional morning care and undo;
- post-workout care;
- History correction preview;
- plan edit preserving history;
- measurement and Progress charts;
- all five CSV export routes;
- loaded/empty/error/iCloud-unavailable states.

Manual/device:

- Apple Numbers opens all five exports and retains Unicode;
- VoiceOver and Accessibility Inspector;
- representative Dynamic Type sizes including accessibility sizes;
- both appearances, Increased Contrast, Reduce Motion, Reduce Transparency,
  grayscale, and common color-vision simulations;
- notification delivery/actions while foregrounded, backgrounded, and terminated;
- offline and two-installation CloudKit scenarios;
- physical-device performance traces.

## 9. Acceptance-criteria traceability

| Product Spec §18 criterion | Current result at `272371f5` | Work required |
|---|---|---|
| 1. Cycle passes recovery, miss, skip, early, edit, delete, cutoff, and time-zone scenarios | Partial | GAP-002, GAP-005, GAP-008, GAP-011, GAP-016 |
| 2. Seed workout and care content matches canonical sources | Partially tested | Full fixture snapshots and manual comparison in GAP-016 |
| 3. Primary logging works offline and survives termination | Fails on ordinary Simulator because store is in memory | GAP-001 plus termination/relaunch UI coverage |
| 4. Private iCloud sync works between two installations | Unverified | GAP-013 and signed-device evidence |
| 5. Pending notifications reflect current plans and Due Workout | Fails; scheduler is not integrated | GAP-002 and GAP-003 |
| 6. History edits recalculate totals, streaks, and next workout | Fails; History is a placeholder | GAP-008 and GAP-009 |
| 7. CSV exports open in Numbers and retain Unicode | Parser/unit checks pass; Numbers unverified | Manual Numbers check in GAP-016 |
| 8. Primary screens pass accessibility and appearance checks | Unverified; three primary screens are placeholders | GAP-008 through GAP-016 |
| 9. No v1 non-goal or product brand appears | No source violation found in audit | Repeat final source/binary audit |

## 10. Recommended implementation sequence

### Phase 0 — Protect persistence and the development environment

1. Fix ordinary Simulator storage.
2. Add explicit preview/test store selection.
3. Add termination/relaunch tests.
4. Repair canonical settings selection and reset/reseed behavior.

Exit criteria:

- ordinary launches use durable data;
- tests opt into isolated stores;
- reset leaves a valid first-launch experience;
- current automated suites remain green.

### Phase 1 — Centralize reconciliation and notifications

1. Complete DailyReconciler workout and care facts.
2. Add duplicate repair.
3. Add reminder derivation.
4. Add notification delegate/actions.
5. Wire every lifecycle and mutation trigger.

Exit criteria:

- reconciliation is idempotent;
- missed/skip facts are correct;
- pending reminders exactly match current state;
- repeated notification actions are safe.

### Phase 2 — Finish the three primary daily flows

1. Complete Today aggregation and full-screen workout presentation.
2. Complete Workout Session prior values, alternatives, progression resolution,
   post-workout care, and optional weight.
3. Complete nutrition totals/finalization/reopen/edit/duplicate/delete.
4. Complete care skip/undo/post-workout integration.

Exit criteria:

- workout, food, and care flows work offline and survive termination;
- Today answers what is due, what can be logged, and current consistency;
- all relevant mutations reconcile reminders.

### Phase 3 — Make history authoritative and correctable

1. Implement History navigation and day detail.
2. Implement correction transactions and schedule previews.
3. Map persisted facts into AdherenceEngine.
4. Implement 16-week heatmap and category streaks.

Exit criteria:

- all historical categories can be corrected safely;
- downstream schedule, totals, heatmap, streaks, and reminders recompute;
- large history remains responsive and accessible.

### Phase 4 — Complete Plans and Progress

1. Implement workout, nutrition, care, and reminder plan editors.
2. Implement manual/post-workout measurements.
3. Implement Progress charts and summaries.
4. Implement milestones.

Exit criteria:

- plan edits affect future facts only;
- Progress contains every required view;
- milestone generation is restrained and idempotent.

### Phase 5 — Sync and release hardening

1. Add CloudKit conflict and duplicate repair evidence.
2. Add migrations and two-installation tests.
3. Complete localization, diagnostics, accessibility, and performance work.
4. Add final icon, signing, privacy validation, and distribution archive.
5. Complete all automated/manual acceptance evidence.

Exit criteria:

- every Product Spec §18 criterion has recorded evidence;
- no known P0/P1 defect remains;
- remaining manual gates, if any, have named owners and exact steps.

## 11. Luna execution rules

- Work on `agent/continue-momentum` or a branch explicitly based on audited SHA
  `272371f5`; do not accidentally implement against the older `master` tree.
- Re-resolve the branch SHA before starting. If it moved, audit the changed files
  and update this document's baseline.
- Preserve the existing schema and pure engines unless a failing requirement
  demonstrates that an interface must change.
- Keep SwiftUI and SwiftData out of pure domain targets.
- Inject clock, Calendar, time zone, and service boundaries in deterministic
  logic.
- Use Calendar arithmetic for Domain Days; never fixed 24-hour seconds.
- Preserve user drafts on recoverable failures.
- Preserve historical snapshots through plan edits.
- Use soft deletion for synchronized historical facts where specified.
- Never solve reconciliation in individual screens; call the centralized,
  idempotent service.
- Never claim CloudKit, notification, accessibility, performance, or Numbers
  verification from unit tests alone.
- Keep focused commits and update this handoff after each completed phase.

## 12. Definition of done

Luna must not report v1 complete merely because the app builds or placeholder
screens have been replaced. Completion requires:

- every P0 and P1 item resolved;
- every required top-level tab and Settings behavior functional;
- primary logging durable offline and through termination;
- Today derived from persisted, reconciled facts;
- notification requests/actions correct and idempotent;
- History corrections recompute every downstream result;
- future-only plan editing and stable historical snapshots;
- all required Progress views, measurements, and milestones;
- five CSV files verified by parser tests and Apple Numbers;
- complete automated suites passing;
- physical-device CloudKit and notification evidence;
- accessibility and appearance verification;
- acceptable target-device performance;
- final icon, privacy manifest, signing, and distribution archive;
- no prohibited product brand, third-party service, network client, analytics,
  or non-goal in the final build.

## 13. Luna kickoff checklist

Before editing:

- [ ] Read the normative sources in §3.
- [ ] Confirm branch and GitHub SHA.
- [ ] Confirm worktree status and preserve unrelated user changes.
- [ ] Run `git diff --check`, `swift test`, simulator build, and Xcode tests.
- [ ] Start with Phase 0 unless newer commits already resolve it.

For every implementation slice:

- [ ] Add or update deterministic tests.
- [ ] Verify CloudKit-compatible schema constraints.
- [ ] Verify Domain Day behavior at the configured cutoff.
- [ ] Preserve drafts on failure.
- [ ] Reconcile state and notifications after mutations.
- [ ] Check accessibility at a representative large Dynamic Type size.
- [ ] Record exact commands and results.

Before handoff:

- [ ] Update gap statuses and acceptance traceability.
- [ ] Record the new exact commit SHA.
- [ ] List physical-device/manual checks separately from automated results.
- [ ] Record unresolved product decisions without guessing.
- [ ] Confirm no unrelated changes were overwritten.
