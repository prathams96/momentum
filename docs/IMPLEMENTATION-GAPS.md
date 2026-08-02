# Momentum Implementation Gaps and Luna Handoff

## 1. Purpose

This document is the implementation handoff for completing Momentum v1. It explains:

- what is present on the canonical GitHub branch;
- what is incomplete, incorrect, or unverified;
- what must be fixed versus newly implemented;
- the required architecture and behavioral constraints;
- the recommended implementation sequence;
- the tests and release evidence required before v1 can be considered complete;
- how to handle the interrupted, uncommitted implementation work currently in the local workspace.

The intended reader is a Luna implementation agent. Treat this as an execution plan, not as a replacement for the normative product documents.

## 2. Canonical baseline

Audit baseline:

- Repository: `prathams96/momentum`
- GitHub default branch: `master` (there is no default `main` branch)
- Audited commit: `8b8c5cc87c8064f3cfda0cdba5c894c22c7dfd47`
- Commit description: merge of PR #1, `Agent/continue momentum`
- Audit date: 2026-08-02

The GitHub baseline builds successfully for the iOS Simulator. Verification against the isolated GitHub commit produced:

- `swift test`: 15 tests passed;
- Xcode application tests: 2 tests passed;
- Xcode UI tests: 1 test passed;
- simulator Debug build: succeeded.

Passing tests only verify the small implemented slice. They do not indicate v1 readiness.

## 3. Normative source order

Read and apply the repository documents in this order:

1. `PRODUCT.md`
2. `CONTEXT.md`
3. `docs/adr/0001-use-a-continuous-recovery-driven-workout-cycle.md`
4. `docs/adr/0002-use-swiftdata-with-private-cloudkit-sync.md`
5. `docs/PRODUCT-SPEC.md`
6. `docs/TECHNICAL-SPEC.md`
7. `DESIGN.md`
8. `UL_4_Day_Workout_Plan.md` for seed exercise content only
9. `Skincare.md` for seed care content only

Precedence rules:

- ADRs govern architecture and scheduling.
- `CONTEXT.md` governs terminology.
- `PRODUCT-SPEC.md` governs user-visible behavior.
- `TECHNICAL-SPEC.md` governs implementation structure, models, algorithms, and verification.
- `DESIGN.md` governs visual and interaction choices.
- Original workout and skincare documents provide seed content only where newer specifications do not override them.

Do not silently invent a product decision when these sources genuinely conflict. Record the conflict and request a decision.

## 4. Nonnegotiable product rules

These rules must remain true throughout implementation:

- The Workout Cycle is continuous: Upper A → Lower A → Upper B → Lower B.
- The cycle never resets on Monday and is never anchored to weekdays.
- Recovery is calculated from the actual Workout Session completion Domain Day.
- Missed and Skipped Workouts never advance the Workout Cycle.
- The same Due Workout remains due until it is finished.
- No catch-up session or double-workout recommendation is generated.
- Start Early is allowed after factual recovery confirmation; it is never blocked.
- Finish Workout always creates a completed session and advances the cycle.
- There is no session-level partial-workout status.
- Food is manually named with manually entered calories and protein.
- Routine and target edits affect future activity only; history retains snapshots.
- Care uses generic roles and active ingredients, never product brands.
- Waiting periods are guidance only; no care timer is created.
- Adapalene frequency never changes automatically.
- Recovery contributes no adherence obligation.
- Notifications are local. There is no application backend, analytics SDK, authentication SDK, or third-party dependency.
- Data remains local-first, private, CloudKit-compatible, and exportable.

## 5. Current GitHub implementation summary

The GitHub baseline is approximately at stage 3 / early stage 4 of the 12-stage implementation order in `docs/TECHNICAL-SPEC.md`.

Implemented on GitHub:

- native iOS 26 SwiftUI project shell;
- iPhone-only bundle configuration for `com.pratham.momentum`;
- SwiftData container configured for private CloudKit;
- iCloud and remote-notification background entitlements;
- pure `DomainDay` implementation with cutoff, DST, and time-zone tests;
- pure `ScheduleEngine` with the basic 0/1/0/2 recovery transitions;
- four tab items with independent `NavigationStack` instances;
- four seeded Workout Templates and exercise prescriptions;
- generic care template seed data;
- seed-version guard and basic idempotency test;
- three-screen onboarding prototype;
- static Today prototype and read-only workout-plan screen.

Not implemented on GitHub:

- primary logging persistence and flows;
- dynamic Today aggregation;
- active workout execution;
- nutrition logging and finalization;
- care occurrence execution;
- reconciliation and notifications;
- History, Plans, Progress, and Settings;
- adherence, progression, charts, milestones, and export;
- complete CloudKit conflict handling and verification;
- release-grade accessibility, localization, privacy, signing, and device validation.

## 6. Gap status matrix

| ID | Area | GitHub status | Priority | Primary dependency |
|---|---|---|---|---|
| GAP-001 | Persistence schema and record mapping | Severely incomplete | P0 | None |
| GAP-002 | Schedule/history integration | Engine exists, integration missing | P0 | GAP-001 |
| GAP-003 | Daily reconciliation | Missing | P0 | GAP-001, GAP-002, GAP-007 |
| GAP-004 | Workout execution and logging | Missing | P0 | GAP-001, GAP-002 |
| GAP-005 | Nutrition logging and finalization | Missing | P0 | GAP-001 |
| GAP-006 | Care execution and recurrence | Templates only | P0 | GAP-001, GAP-003 |
| GAP-007 | Onboarding | Partial and error-prone | P0 | GAP-001, GAP-009 |
| GAP-008 | Today | Static prototype | P0 | GAP-002 through GAP-006 |
| GAP-009 | Notifications | Missing | P1 | GAP-003 through GAP-006 |
| GAP-010 | History and correction | Missing | P1 | GAP-001 through GAP-006 |
| GAP-011 | Adherence, heatmap, and streaks | Missing | P1 | GAP-003, GAP-010 |
| GAP-012 | Measurements, Progress, and milestones | Missing | P1 | GAP-001, GAP-011 |
| GAP-013 | Plans and Settings | Missing | P1 | GAP-001 through GAP-009 |
| GAP-014 | CSV export | Missing | P1 | GAP-001, GAP-010, GAP-011 |
| GAP-015 | CloudKit conflicts and sync verification | Configuration only | P1 | Stable schema and flows |
| GAP-016 | Accessibility, localization, design, and performance | Partial/unverified | P1 | All primary screens |
| GAP-017 | Error handling and diagnostics | Mostly missing | P1 | Service boundaries |
| GAP-018 | Release validation and signing | Missing | P1 | All implementation |

## 7. Detailed implementation requirements

### GAP-001 — Complete the persistence schema and mapping layer

#### Current condition

The GitHub schema contains only seven models:

- `AppSettingsRecord`
- `WorkoutTemplateRecord`
- `CycleAnchorRecord`
- `ExercisePrescriptionRecord`
- `ExerciseAlternativeRecord`
- `CareRoutineTemplateRecord`
- `CareTaskTemplateRecord`

This is insufficient for any durable logging flow or historical truth.

#### Required implementation

Add and register the complete v1 record set from Technical Spec §5:

Configuration:

- `NutritionTargetRecord`
- expanded `AppSettingsRecord` notification, appearance, and iCloud metadata

Workout history:

- `WorkoutSessionRecord`
- `ExerciseLogRecord`
- `SetLogRecord`
- `WorkoutDayEventRecord`
- `LoadSuggestionRecord`

Nutrition:

- `FoodPresetRecord`
- `FoodEntryRecord`
- `NutritionDayRecord`

Care:

- `CareOccurrenceRecord`
- `CareTaskCompletionRecord`

Measurements and milestones:

- `BodyMeasurementRecord`
- `MilestoneRecord`

#### Required constraints

- Every model has a UUID `id`; do not use `@Attribute(.unique)`.
- Avoid required SwiftData relationships. Prefer UUID foreign keys.
- Provide CloudKit-compatible defaults for stored values.
- Include `createdAt` and `updatedAt` consistently.
- Add `deletedAt` for soft-deletable history.
- Persist raw enum strings and decode unknown values to a safe default or repair state.
- Preserve snapshot fields for historical names, prescriptions, targets, alternatives, notes, sequence positions, and recovery configuration.
- Persist calculated food totals but recompute them whenever base values or serving multiplier change.
- Store Nutrition Targets as effective-dated records, not mutable fields on settings.
- Keep adherence and streaks derived; do not persist them as authoritative state.

#### Singleton and duplicate repair

Implement deterministic repair for duplicate settings, active targets, anchors, occurrences, events, and open sessions:

- choose the greatest `updatedAt` where a latest-record rule is appropriate;
- merge only safe fields;
- tombstone or exclude duplicates deterministically;
- record diagnostics without exposing implementation terminology in the UI;
- never assume CloudKit transaction order.

#### Required tests

- in-memory ModelContainer construction for the full schema;
- insert/fetch/update/delete coverage for every record type;
- soft-delete exclusion;
- calculated Food Entry totals;
- effective target resolution by Domain Day;
- seed migration and seed-version idempotency;
- duplicate-settings and duplicate-anchor repair;
- migration tests from every released schema version before production promotion.

### GAP-002 — Connect ScheduleEngine to persisted history

#### Current condition

The pure ScheduleEngine exists, but Today bypasses it and reads only the initial Cycle Anchor. There are no persisted Workout Sessions to evaluate.

The current historical engine input also depends on the source Workout Template remaining active. This is unsafe when a completed template is archived or removed.

#### Required implementation

- Map active `WorkoutTemplateRecord` values to pure engine inputs.
- Map nondeleted completed `WorkoutSessionRecord` values to pure historical inputs.
- Pass an unfinished active session ID when exactly one exists.
- Use the Cycle Anchor only when no completed session exists.
- Preserve session sequence, recovery, and successor snapshots so future plan edits do not make historical scheduling impossible.
- Keep missed and skipped events out of cycle advancement; use them only for adherence/history.
- Return and surface `.needsRepair` when the facts are genuinely impossible.
- Provide a safe duplicate-open-session repair flow rather than discarding either session automatically.

#### Historical mutation behavior

Before editing or deleting a completed session:

1. evaluate the current schedule;
2. evaluate a projected schedule with the proposed mutation;
3. display the resulting next workout and due date;
4. require confirmation;
5. commit the mutation transactionally;
6. rebuild day events, occurrences, adherence, and notifications.

#### Required tests

In addition to current tests, cover:

- missed and skipped events retaining the same workout;
- early completion anchoring future recovery to the actual completion day;
- editing and deleting the latest session;
- archiving or deleting the latest session's source template;
- reordered templates;
- week, month, year, DST, cutoff, and time-zone boundaries;
- long gaps without catch-up;
- duplicate open sessions;
- invalid or empty cycle repair.

### GAP-003 — Implement DailyReconciler

#### Current condition

No lifecycle reconciliation exists on GitHub. Care occurrences, missed workout events, rolling hair care, and notification cleanup therefore cannot work.

#### Required implementation

Implement one idempotent `DailyReconciler` invoked:

- after onboarding;
- on scene activation;
- after significant time changes;
- after settings or routine edits;
- after historical edits;
- after relevant CloudKit imports become visible.

The reconciler must:

1. calculate the current Domain Day using the configured cutoff;
2. create missing Care Occurrences in a bounded window;
3. mark yesterday's nonrolling pending care as missed;
4. roll missed hair care forward exactly once;
5. create a Missed Workout Day Event when a prior Due Workout opportunity elapsed without completion or explicit skip;
6. enforce one logical occurrence/event per composite key and repair duplicates;
7. reconcile all pending notifications;
8. remain safe to run repeatedly.

Do not use fixed 24-hour arithmetic.

#### Required tests

- repeated reconciliation produces no duplicates;
- nonrolling care expires once;
- hair care rolls exactly once;
- a rolled hair miss still breaks the original care streak;
- skip prevents an automatic missed event for the same opportunity;
- recovery days never create missed workout events;
- cutoff, DST, time-zone, and CloudKit duplicate scenarios.

### GAP-004 — Implement Workout Session execution

#### Current condition

The GitHub “Start Workout” action opens a read-only plan. No session is created, no sets can be entered, and the cycle cannot advance.

#### Required implementation

Starting a workout must:

- create a `WorkoutSessionRecord` immediately;
- snapshot the workout name, focus, sequence position, recovery requirement, and intended successor;
- snapshot active Exercise Prescriptions, selected alternatives, set counts, rep ranges, and notes;
- create working Set Log drafts;
- present an immersive full-screen session flow;
- survive app termination and resume from Today.

For each working set, support:

- weight in kilograms;
- repetitions;
- reps in reserve;
- completed or skipped status;
- optional note.

Also implement:

- previous-session values and a copy action;
- exercise-level skip;
- configured alternative selection without changing history;
- stable field ordering and appropriate numeric keyboards;
- large-type vertical reflow;
- checkpoint persistence without saving on every keystroke;
- one persistent Finish Workout action.

Finish behavior:

- always records a completed session;
- shows factual confirmation if any sets remain unfinished;
- converts remaining set/exercise drafts to a clear final state;
- records the actual completion Domain Day;
- advances the cycle through recomputation;
- triggers progression suggestions;
- asks the post-workout care questions;
- offers optional post-workout weight entry;
- refreshes reconciliation and notifications.

#### Required tests

- start, terminate, relaunch, and resume;
- complete all sets;
- finish with unfinished or skipped sets;
- alternative selection retains snapshots;
- previous values and copy;
- early start;
- finish always advances exactly once;
- no session-level partial status;
- post-workout care and weight prompts;
- UI coverage for accessibility text sizes.

### GAP-005 — Implement nutrition logging and finalization

#### Current condition

Today displays only static nutrition copy. No Food Entry, preset, total, target, or finalization record exists on GitHub.

#### Required implementation

Food Entry sheet:

- required name;
- nonnegative whole-number base calories;
- nonnegative decimal base protein;
- serving multiplier greater than zero, default 1.0;
- editable timestamp and Domain Day for backdating;
- inline validation;
- draft retention and Retry on save failure.

Reuse behavior:

- recent foods sorted by last use;
- explicit favorites pinned first;
- selection prepopulates editable values;
- favorite/unfavorite support;
- duplicate support;
- swipe-to-delete with downstream-safe recalculation.

Nutrition Day behavior:

- display consumed calories against the green range;
- display consumed protein against the minimum;
- identify open versus finalized state;
- Finish Logging Today creates explicit finalization and snapshots the applicable targets;
- finalized entries remain editable;
- editing recalculates totals and adherence;
- support reopening a finalized day without losing history;
- schedule the 22:00 unfinished reminder;
- coalesce with night care when both are due at the same time.

#### Required tests

- calorie/protein validation boundaries;
- serving multipliers and persisted totals;
- recent/favorite sorting;
- duplicate/edit/delete;
- finalization and reopening;
- edits after finalization;
- effective target snapshots;
- Unicode names and offline persistence.

### GAP-006 — Implement care recurrence and execution

#### Current condition

Care templates and tasks are seeded, but there are no occurrences or task completions. Today labels rows by sorted position rather than routine identity.

#### Required implementation

Recurrence representation:

- replace ad-hoc recurrence strings with a versioned Codable payload;
- support daily, weekday-set, and alternating interval schedules;
- decode unknown versions safely and route to an editor repair state;
- store enough alternating-cadence state to continue 3/4-day intervals from actual completion after a rolled occurrence.

Occurrence execution:

- one occurrence represents one Due Care Routine;
- snapshot routine name and task labels/instructions;
- show tasks in order;
- support conditional cleanse paths where selecting one valid variant fulfills the group;
- treat waiting guidance as text only;
- conditional tasks that do not apply must not reduce adherence;
- allow undo from Today and History;
- allow whole-routine completion from a notification idempotently;
- support Skip Today and rolling only when the schedule requires it.

Seed corrections:

- select routines by stable identity, category, or recurrence—not sorted array position;
- preserve exact morning/night weekday assignments;
- retain generic roles and active ingredients;
- ensure no brands or paused glycolic-acid tasks enter active seed data;
- never seed automatic adapalene progression.

Post-workout care:

- ask “Heavy sweating?” after Finish Workout;
- if yes, add Wash Face to Today;
- ask “Going outdoors again?”;
- if yes, also add Reapply Sunscreen.

#### Required tests

- every weekday routine mapping;
- morning conditional group completion;
- alternating 3/4 cadence;
- rolled hair occurrence exactly once;
- actual-completion cadence reset;
- notification Done idempotency and undo;
- post-workout conditional generation;
- unknown recurrence version repair.

### GAP-007 — Complete and harden onboarding

#### Current condition

GitHub onboarding contains only three broad screens. It hard-codes Upper A as next, omits notification and iCloud configuration, and uses `try? modelContext.save()`.

#### Required implementation

The first-launch flow must:

1. explain private, local-first, single-person behavior;
2. preview the seeded Workout Cycle and care routines;
3. allow selection of which workout is next, defaulting to Upper A;
4. ask whether the next workout is due today, defaulting to yes;
5. edit 2,400 kcal, 2,300–2,500 kcal, and 150 g starting targets;
6. edit all seeded notification times;
7. explain notification value before requesting authorization;
8. show iCloud state and allow local-only continuation;
9. persist all decisions atomically;
10. run reconciliation and schedule reminders after completion.

Validation and failure behavior:

- calorie minimum must not exceed maximum;
- all target values must be nonnegative and meaningful;
- notification denial must not block completion;
- save failure must retain the draft and offer Retry/Cancel;
- do not mark onboarding complete in memory if persistence fails;
- avoid duplicate anchors, targets, or templates if onboarding is retried.

Do not add signup, profile creation, measurement demands, or a tutorial carousel.

### GAP-008 — Replace static Today with real aggregation

#### Current condition

Today is a visual prototype. It reads the initial anchor directly, displays placeholder nutrition/care rows, and renders 16 decorative bars instead of a seven-row heatmap.

#### Required implementation

Implement a small `@MainActor @Observable` Today aggregation store or equivalent narrow state layer. It should consume persisted facts and pure engines outside the View body.

Content order must be:

1. large Today title and Domain Day date;
2. Due Workout, Recovery Day, or active-session state;
3. nutrition progress with visible Log Food action;
4. Due Care Routines ordered by time;
5. compact 16-week heatmap and current category streaks.

Workout states:

- Due: name, focus, due/overdue text, exercise count, Start Workout;
- Recovery: explicit label, next workout, eligible Domain Day, Start Early;
- Overdue: same workout retained; no catch-up;
- Active: Resume Workout;
- Needs Repair: safe explanation and repair route.

Nutrition state:

- total calories and green range;
- total protein and minimum;
- open/finalized state;
- Log Food and Finish/Reopen Logging actions.

Care state:

- actual generated occurrences only;
- correct routine names and times;
- task expansion or focused sheet;
- completion, skip, and undo state.

Consistency:

- 16 weeks initially;
- seven weekday rows by week columns;
- horizontal access to older data;
- five intensity levels;
- distinct no-obligation and 0%-completion states;
- numeric and VoiceOver detail;
- current Workout, Nutrition, and Personal Care streaks.

Correct the current defects:

- use Domain Day, not raw `Date.now`, for the header date;
- do not label a future workout as Due;
- do not always show Start Workout during recovery;
- do not infer care names from sorted positions;
- do not use Data Cyan outside chart comparison;
- use sentence-case action labels.

### GAP-009 — Implement local notifications and actions

#### Current condition

Entitlements exist, but no notification scheduler, categories, delegate, action handling, reconciliation, or permission-status UI exists on GitHub.

#### Required implementation

Register categories:

- `WORKOUT_DUE`: Start, Remind in 30 Minutes, Skip Today;
- `CARE_DUE`: Done, Remind in 30 Minutes, Skip Today;
- `EVENING_CHECKIN`: Open Today, Remind in 30 Minutes.

Scheduling rules:

- schedule only the next actionable workout reminder;
- use repeating triggers only for truly identical stable daily care;
- use bounded one-shot occurrences otherwise;
- hair care is always one-shot;
- stable identifiers derive from notification kind plus record ID/Domain Day;
- cancel obsolete requests immediately;
- reschedule after every relevant mutation and app activation;
- coalesce night care and unfinished nutrition at 22:00;
- never let denial block the app.

Action handling:

- route actions through one notification delegate;
- write via the main ModelContext;
- make care Done idempotent;
- create explicit skip events;
- snooze exactly 30 minutes;
- run DailyReconciler after mutations;
- refresh visible state and pending requests.

#### Required tests

- deterministic identifiers;
- stale request cancellation;
- only one workout reminder;
- hair one-shot cadence;
- 22:00 coalescing;
- Done, Skip, Snooze, and denial behavior;
- notification actions while the app is terminated or backgrounded;
- physical-device verification.

### GAP-010 — Implement History and correction flows

#### Current condition

History is a `ContentUnavailableView` placeholder.

#### Required implementation

History must provide:

- all-category heatmap;
- category filter;
- calendar navigation;
- chronological Domain Day detail;
- workouts, food, care, and measurements;
- backdating, editing, duplication where relevant, and deletion;
- explicit destructive confirmation;
- explanation of downstream effects;
- practical same-session undo;
- completed-workout schedule preview before mutation.

Queries should fetch only the relevant visible date range where practical. Day bucketing and sorting must occur outside View bodies.

#### Required tests

- category filters and calendar navigation;
- edit/delete/backdate for every record family;
- finalized nutrition recalculation;
- care undo;
- workout schedule preview and recalculation;
- Unicode and large histories;
- destructive confirmation copy.

### GAP-011 — Implement adherence, heatmap, streaks, and milestones

#### Current condition

The GitHub heatmap is decorative. No AdherenceEngine, category-specific streak logic, or milestones exist.

#### Required implementation

Adherence score:

- gather Due Workout, nutrition finalization, due care, and generated post-workout care facts;
- weight each due activity equally;
- treat recovery as no workout obligation;
- treat skipped and missed as incomplete;
- represent a day with no obligations as no-obligation, not 0%;
- calculate pure deterministic output.

Category streaks:

- Workout: consecutive Due Workout opportunities completed; Recovery Days neutral; Missed or Skipped breaks;
- Nutrition: consecutive finalized Domain Days;
- Care: consecutive Domain Days where all due Care Routines completed; a rolled hair miss breaks the original day.

Milestones:

- 10, 25, and 50 completed workouts;
- new category-streak records;
- exercise bests;
- consecutive days within Nutrition Target Range;
- acknowledge once, with restrained presentation;
- no coins, levels, confetti, streak freezes, or punitive loss copy.

#### Required tests

- equal weighting;
- no-obligation days;
- recovery neutrality;
- miss and skip behavior;
- rolled hair behavior;
- at least 18 months of fixtures;
- deterministic historical recalculation;
- milestone idempotency.

### GAP-012 — Implement measurements and Progress

#### Current condition

Progress is a placeholder and there is no measurement persistence.

#### Required implementation

Measurements:

- manual weight in kilograms;
- optional waist circumference in centimeters;
- post-workout weight source;
- editable/backdatable history;
- seven-day weight average when enough data exists;
- raw observations shown alongside the average;
- waist due indication after seven days without a notification;
- neutral, nonjudgmental trend language.

Progress views:

- raw weight and seven-day average;
- waist history;
- daily calories with target range;
- daily protein with minimum;
- exercise volume over time;
- highest completed weight;
- best repetitions at each weight;
- adherence and category-streak history.

Use Swift Charts. Preaggregate outside View bodies, include accessible RuleMarks and textual summaries, and never compute estimated one-repetition maximums.

### GAP-013 — Implement Plans and Settings

#### Current condition

Plans is a placeholder. Settings is absent and there is no Today toolbar entry.

#### Required implementation

Plans:

- reorder the Workout Cycle;
- maintain contiguous sequence indices and at least one active template;
- add, remove, reorder, and edit exercises;
- configure alternatives;
- edit set counts, rep ranges, notes, RIR bounds, load increments, optional state, and recovery days;
- edit effective-dated nutrition targets;
- edit care recurrence, task order, generic role/active, instructions, and notification time;
- preserve all historical snapshots.

Settings:

- notification permission/status and times;
- Domain Day cutoff;
- time-zone attribution-change confirmation;
- metric units seeded as kg/cm;
- appearance selection;
- iCloud status: Syncing, Synced recently, iCloud unavailable, or Local only;
- CSV export;
- About and data explanation;
- typed destructive Reset All Data confirmation.

Settings must be reached from the Today toolbar, not a fifth tab.

### GAP-014 — Implement CSV export

#### Current condition

No export service or UI exists on GitHub.

#### Required implementation

Generate UTF-8 RFC 4180 files:

- `workouts.csv`
- `food.csv`
- `measurements.csv`
- `care.csv`
- `adherence.csv`

Requirements:

- immutable DTO input;
- stable English headers;
- stable record IDs;
- ISO 8601 timestamps;
- Domain Day column;
- snapshot values sufficient to understand history outside the app;
- deletion status where relevant;
- period decimal separator via `en_US_POSIX`;
- native share sheet;
- stale temporary export cleanup on a later launch or conservative age threshold.

#### Required tests

- commas, quotes, CR/LF, and Unicode;
- decimal formatting under non-English locales;
- headers and required columns;
- soft-deleted row behavior;
- parse every file with an independent CSV parser;
- manually open all files in Apple Numbers.

### GAP-015 — Complete CloudKit behavior and verification

#### Current condition

The private CloudKit configuration and entitlements exist, but sync behavior, conflict repair, status, migration, and two-installation evidence do not.

#### Required implementation

- create the production ModelContainer exactly once at app root;
- retain a local replica when iCloud is unavailable;
- never claim a write has reached the cloud immediately;
- display sync status only in Settings unless action is required;
- reconcile latest-`updatedAt` settings edits;
- keep completed history append-mostly;
- preserve soft deletes across devices;
- recompute schedules and adherence from reconciled facts;
- surface a Needs Repair flow for impossible cycle order or duplicate open sessions;
- initialize and inspect the development CloudKit schema;
- promote only after schema and migration acceptance.

#### Required verification

- two physical installations on the same Apple ID;
- offline create/edit/delete followed by reconnection;
- concurrent settings edits;
- duplicate singleton records;
- duplicate open sessions;
- schema migration from every released version;
- development schema inspection before production promotion.

### GAP-016 — Accessibility, localization, design, and performance

#### Current condition

The prototype uses semantic fonts in many places, but the full accessibility matrix, localization resources, assets, and performance evidence are missing.

#### Required implementation

Accessibility:

- Dynamic Type through accessibility sizes;
- 44-by-44-point minimum targets;
- complete VoiceOver labels and logical reading order;
- non-color cues for every state;
- Reduce Motion and Reduce Transparency behavior;
- Increased Contrast and grayscale distinguishability;
- reflow dense set rows vertically;
- textual chart summaries;
- heatmap date, score, and completed/due details.

Localization:

- add `Localizable.xcstrings`;
- move all user-visible strings into localization resources;
- do not concatenate localized sentence fragments;
- use sentence case consistently.

Design:

- use named color assets with light/dark variants;
- reserve Data Cyan for chart comparison;
- keep content opaque;
- reserve glass for native navigation and interactive surfaces;
- maintain one prominent primary action per screen;
- avoid nested cards, decorative glass, gradients, and hard-coded font sizes;
- provide final app icon artwork matching `DESIGN.md`.

Performance:

- use stable record identity;
- use lazy containers for heatmaps and long history;
- aggregate and sort outside View bodies;
- narrow Observation scope;
- instrument Today, reconciliation, heatmap, and CloudKit imports with OSLog signposts;
- profile Today, Workout Session, and 52-week heatmap scrolling on the target device.

### GAP-017 — Error handling and diagnostics

#### Current condition

Onboarding swallows save errors, and ModelContainer startup failure offers no Retry or diagnostics export.

#### Required implementation

- define typed service-boundary errors;
- translate errors into short recovery copy;
- preserve every editable draft after a recoverable save failure;
- offer Retry and Cancel without dismissing data;
- retain plans when notification scheduling fails;
- disable only the invalid care occurrence on recurrence corruption;
- keep both sessions while resolving duplicate active sessions;
- offer Retry and local diagnostics export when ModelContainer creation fails;
- never create a second store silently over a failed first store;
- never log food names, notes, measurements, or skincare state with OSLog.

### GAP-018 — Release validation and signing

#### Current condition

Simulator builds pass. No paid development team is configured in `project.yml`, and there is no physical-device, CloudKit, notification, or release checklist evidence.

#### Required implementation and verification

- configure the Routine Owner's paid Apple Developer team;
- verify the exact bundle ID and iCloud container;
- include a correct privacy manifest;
- provide final app icon assets;
- build and run on the target iPhone class;
- complete CloudKit development schema initialization and promotion;
- run all unit, persistence, UI, accessibility, and visual tests;
- verify light/dark appearances and every required accessibility setting;
- verify offline termination/relaunch for all logging flows;
- verify notification actions on a physical device;
- verify all CSV files in Numbers;
- ensure no v1 non-goal, product brand, analytics, network client, or third-party dependency appears in the binary.

## 8. Concrete defects to fix before adding more UI polish

These are implemented behaviors on GitHub that are already incorrect:

1. **Care times are mislabeled.** Today sorts routines by notification time, then labels array positions as Morning and Night. The first routine is Hair care at 08:00, so the UI displays incorrect names/times.
2. **The Today date ignores Domain Day.** The header formats `Date.now`, which disagrees with the 03:00 cutoff between midnight and 02:59.
3. **Future workouts are presented as Due.** A future anchor date should produce explicit Recovery state with Start Early.
4. **The ScheduleEngine is bypassed by Today.** UI logic reads the anchor directly and cannot support completed or active sessions.
5. **Start Workout does not start a session.** It opens a read-only plan.
6. **Onboarding save errors are swallowed.** `try? modelContext.save()` can leave an apparently completed but unsaved flow.
7. **Nutrition targets are stored on settings.** This prevents effective dating and historical truth.
8. **Care recurrence payloads are unversioned ad-hoc strings.** Unknown versions cannot be repaired safely.
9. **One seed prescription loses units.** “Side Plank or Pallof Press” stores only 8–15 reps, while Side Plank requires 20–45 seconds.
10. **Several primary actions use title case.** The design system requires sentence case.
11. **Data Cyan is used for a non-chart activity icon.** It is reserved for chart comparison.
12. **Startup failure has no Retry.** The current fallback only asks the Routine Owner to reopen the app.

## 9. Interrupted local WIP overlay

### Important warning

The local workspace is not clean. It contains uncommitted work created after the GitHub audit and before an interrupted implementation turn. This work is not part of commit `8b8c5cc`, is not fully integrated, and must not be represented as completed until independently reviewed and verified.

Do not reset, discard, or overwrite these changes. Start with:

```bash
git status --short
git diff --stat
git diff --check
```

Then review each changed/new file against the current specs and reconcile it deliberately.

### WIP areas present locally

The local overlay appears to include partial implementations for:

- expanded SwiftData schema and ModelContainer registration;
- schedule snapshot hardening;
- `NutritionCalculator`;
- `ProgressionEngine`;
- `AdherenceEngine`;
- versioned care schedule primitives;
- RFC 4180 CSV encoding;
- shared Domain Day string conversion;
- `NotificationScheduler`;
- a partial `DailyReconciler`;
- `WorkoutSessionView`;
- `FoodEntrySheet`;
- `CareRoutineSheet`;
- expanded onboarding;
- Settings and reset services;
- CSV export service;
- localization catalog, privacy manifest, and color/app-icon asset structure;
- additional unit tests.

### WIP gaps and integration risks

- `TodayView` and `AppShell` remain unchanged from the GitHub prototype and do not wire these features together.
- History, Plans, and Progress implementations are not present.
- New source/resource files are not guaranteed to be included in the checked-in Xcode project.
- `project.yml` has changes, but `Momentum.xcodeproj` has not been regenerated after all new files were created.
- The final app icon artwork is not present; only an asset structure may exist.
- Physical-device signing, CloudKit, notification, accessibility, and performance checks remain outstanding.
- Some WIP code was created concurrently; public APIs and ownership boundaries may not align.
- Treat previously reported test results as hints only. Rerun the complete suite after integration.
- Review the partial DailyReconciler carefully; alternating hair cadence needs enough persisted phase state to remain correct after rolled completion on an arbitrary weekday.
- Review the partial Workout Session UI for Dynamic Type reflow, previous values, alternatives, progression, post-workout care, and save checkpoints.
- Verify Reset All Data semantics against CloudKit propagation before enabling it.

### Safe integration procedure

1. Preserve the dirty worktree and capture `git diff` for review.
2. Regenerate the Xcode project from `project.yml` only after checking that xcodegen output will not discard unrelated project settings.
3. Compile the full app before wiring additional screens.
4. Run `swift test` and Xcode tests.
5. Review every new WIP module against its gap section in this document.
6. Fix model/API inconsistencies before building more UI on top.
7. Integrate one vertical slice at a time, keeping tests green.
8. Commit coherent slices; do not create a single undifferentiated “finish app” commit.

## 10. Recommended implementation sequence

### Phase 1 — Stabilize and integrate the local foundation

1. Inventory and review all WIP changes.
2. Complete the CloudKit-safe schema.
3. Resolve model/API mismatches across persistence and pure engines.
4. Regenerate the Xcode project and include resources.
5. Restore a clean simulator build and complete test run.
6. Fix current correctness defects before adding new presentation polish.

Exit criteria:

- all 20 models registered and tested;
- new source files compile in the real project;
- package and Xcode tests pass;
- no swallowed persistence errors;
- no duplicate seed records;
- no unintended deletion of local WIP.

### Phase 2 — Complete the workout vertical slice

1. Persisted schedule mapping.
2. Dynamic Due/Recovery/Active Today state.
3. Start/Resume/Finish Workout flow.
4. Set and exercise logging.
5. cycle advancement and progression suggestion.
6. missed/skip/early behavior.
7. post-workout care and optional weight.
8. History correction preview.

Exit criteria:

- all workout acceptance scenarios pass offline and after termination;
- no catch-up or weekday reset behavior exists;
- active sessions resume reliably;
- historical edits preview and recompute the schedule.

### Phase 3 — Complete nutrition and care vertical slices

1. Food Entry, presets, favorites, editing, deletion, and duplication.
2. Nutrition totals, targets, finalization, and reopening.
3. care recurrence and occurrence generation.
4. conditional care execution and undo.
5. rolling hair behavior.
6. DailyReconciler integration.
7. notification scheduling and actions.

Exit criteria:

- both categories work offline and survive termination;
- reconciliation is idempotent;
- notification requests always match current plans/state;
- finalized/history edits recalculate derived output correctly.

### Phase 4 — Complete exploration, planning, and export

1. History and day detail.
2. adherence, heatmap, and streaks.
3. measurements and Progress charts.
4. milestones.
5. Plans editors.
6. Settings.
7. CSV export.

Exit criteria:

- all four tabs are functional;
- Settings is available from Today;
- plan edits preserve history;
- all five exports parse and open in Numbers;
- charts have accessible summaries.

### Phase 5 — CloudKit, accessibility, performance, and release

1. duplicate/conflict repair.
2. physical two-device sync and offline/reconnect tests.
3. localization and copy audit.
4. VoiceOver and Dynamic Type audit.
5. motion/transparency/contrast audit.
6. performance profiling and signposts.
7. final assets, privacy manifest, signing, and distribution build.

Exit criteria:

- every Product Spec §18 acceptance criterion has recorded evidence;
- complete automated tests pass;
- required manual/device checks are documented;
- no known P0/P1 defects remain.

## 11. Acceptance-criteria traceability

| Product acceptance criterion | Current GitHub result | Required evidence |
|---|---|---|
| Continuous cycle passes recovery, miss, skip, early, edit, delete, cutoff, and time-zone scenarios | Partial pure tests only | Unit, persistence, and UI scenario suite |
| Seed workouts and care tasks match canonical sources | Partial; one known unit mismatch | Snapshot tests and manual source comparison |
| Primary logging works offline and survives termination | Fails; logging absent | Termination/relaunch tests for workout, food, care, measurement |
| Private iCloud sync works across two installations | Unverified | Two-device evidence on same Apple ID |
| Pending notifications reflect current plans and Due Workout | Fails; scheduler absent | Pending-request tests and physical-device scenarios |
| History edits recalculate totals, streaks, and next workout | Fails; History absent | Before/after engine, persistence, and UI tests |
| CSV exports open in Numbers and retain Unicode | Fails; export absent | Parser tests plus Numbers verification |
| Primary screens pass accessibility/appearance checks | Unverified | Inspector, VoiceOver, Dynamic Type, motion, transparency, contrast evidence |
| No v1 non-goal or product brand appears | Currently broadly compliant | Final source and binary audit |

## 12. Definition of done for Luna

Luna should not report the application complete merely because it builds or because placeholder screens have been replaced.

Completion requires:

- every P0 and P1 gap in this document resolved or explicitly accepted as an external/manual release gate;
- every primary flow persisted, offline-capable, and termination-safe;
- historical truth preserved through snapshots and future-only plan edits;
- dynamic Today content derived from persisted facts and pure engines;
- reconciliation and notifications correct and idempotent;
- History corrections recalculate all downstream state;
- all four tabs and Settings functional;
- all five CSV exports verified;
- package, app, persistence, and UI tests passing;
- physical-device CloudKit and notification verification completed;
- accessibility and visual validation completed;
- signed distribution configuration completed;
- no prohibited feature, product brand, third-party service, network client, analytics, or privacy violation present;
- the workspace is left in a coherent, reviewable state with focused commits and an updated handoff/status note.

## 13. Luna kickoff checklist

Before editing:

- [ ] Read all normative documents in the stated order.
- [ ] Confirm GitHub baseline commit and current branch.
- [ ] Inspect and preserve the dirty local WIP.
- [ ] Run `git diff --check`.
- [ ] Run `swift test`.
- [ ] Regenerate or inspect the Xcode project only after reviewing `project.yml`.
- [ ] Run simulator build and Xcode tests.
- [ ] Compare local WIP APIs with the full persistence model and engine requirements.
- [ ] Choose the first coherent vertical slice; recommended: schema → schedule mapping → workout execution.
- [ ] Add or update tests before marking each slice complete.

During implementation:

- [ ] Keep Domain Day arithmetic Calendar-based.
- [ ] Keep SwiftData/SwiftUI out of pure engines.
- [ ] Preserve CloudKit-compatible schema constraints.
- [ ] Keep user drafts on recoverable failures.
- [ ] Reconcile notifications after every relevant mutation.
- [ ] Avoid global mutable AppState.
- [ ] Keep history snapshots immutable except through explicit correction flows.
- [ ] Verify every new screen at an accessibility Dynamic Type size.
- [ ] Commit coherent slices and keep tests green.

Before handoff:

- [ ] Update this document's gap statuses.
- [ ] Record exact test/build commands and results.
- [ ] List any physical-device or external verification still required.
- [ ] Identify any product decision that remains unresolved.
- [ ] Confirm no unrelated user changes were overwritten.
