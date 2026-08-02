# Momentum Technical Specification

## 1. Architecture decision summary

Build Momentum as a native SwiftUI app with Apple frameworks only:

- Swift 6 language mode
- SwiftUI for interface and navigation
- Observation for feature state
- SwiftData for local persistence
- private CloudKit database for synchronization
- UserNotifications for local reminders and actions
- Swift Charts for trends
- OSLog for local diagnostics
- XCTest and XCUITest for verification

Minimum deployment target is iOS 26.0. No compatibility layer for earlier iOS releases is required. The app must contain no network client, analytics SDK, authentication SDK, or third-party dependency.

Apple’s current SwiftData guidance requires iCloud and Background Modes/remote-notification capabilities for automatic CloudKit sync and notes that CloudKit-compatible schemas cannot use unique constraints or required relationships. Production CloudKit schemas are additive, so schema design and migration tests must precede production promotion. See [Apple: Syncing model data across a person’s devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).

## 2. Xcode configuration

| Setting | Value |
|---|---|
| Product name | Momentum |
| Bundle identifier | `com.pratham.momentum` |
| Deployment target | iOS 26.0 |
| Devices | iPhone only |
| Primary test device | iPhone 16 Pro Max, iOS 26.0.1 |
| Orientation | Portrait required; landscape supported where system layout permits |
| Storage | SwiftData local store |
| Cloud container | `iCloud.com.pratham.momentum` |
| Cloud database | Private |
| Signing | Automatic signing with the Routine Owner’s paid developer team |

Required capabilities:

- iCloud → CloudKit → `iCloud.com.pratham.momentum`
- Background Modes → Remote notifications, solely for CloudKit synchronization
- Push Notifications is not required for product reminders; reminders are local

Before distribution, initialize the development CloudKit schema, inspect it in CloudKit Console, run sync tests, and promote it to production only after the v1 schema is accepted.

## 3. Source organization

Use a feature-first structure with a small shared core:

```text
Momentum/
  App/
    MomentumApp.swift
    AppShell.swift
    AppTab.swift
    AppRouter.swift
    AppDependencies.swift
  Core/
    Domain/
      DomainDay.swift
      ScheduleEngine.swift
      AdherenceEngine.swift
      NutritionCalculator.swift
      ProgressionEngine.swift
    Persistence/
      SchemaV1.swift
      ModelContainerFactory.swift
      SeedData.swift
      RecordMappers.swift
    Notifications/
      NotificationScheduler.swift
      NotificationCategories.swift
      NotificationDelegate.swift
    Export/
      CSVExportService.swift
    DesignSystem/
      Theme.swift
      Spacing.swift
      Components/
    Support/
      AppClock.swift
      Diagnostics.swift
  Features/
    Onboarding/
    Today/
    WorkoutSession/
    Nutrition/
    Care/
    History/
    Plans/
    Progress/
    Settings/
  Resources/
    Assets.xcassets
    Localizable.xcstrings
MomentumTests/
  Domain/
  Persistence/
  Notifications/
  Export/
MomentumUITests/
```

Do not create a “Manager” or “ViewModel” for every screen. Use:

- `@State` for local UI state and form drafts;
- `@Binding` for parent-owned value state;
- `@Query` for simple persisted lists;
- small `@MainActor @Observable` stores only for multi-step flows such as active workouts and Today aggregation;
- `@Environment` for genuinely shared services: clock, notification scheduler, export service, and router;
- initializer injection for feature-local engines and fixtures.

No global mutable `AppState` object may own all features.

## 4. Navigation and presentation

`AppShell` owns a `TabView` with Today, History, Plans, and Progress. Each tab owns an independent `NavigationStack` path. Routes store stable IDs, never View instances.

```swift
enum AppTab: Hashable, CaseIterable {
    case today, history, plans, progress
}

enum AppRoute: Hashable {
    case dayDetail(DomainDay)
    case workoutDetail(UUID)
    case exerciseProgress(UUID)
    case careHistory(UUID)
    case settings
}

enum SheetDestination: Identifiable, Hashable {
    case logFood(existingID: UUID?)
    case logMeasurement(kind: MeasurementKind)
    case editWorkout(UUID)
    case editCareRoutine(UUID)
    case editTargets
    case export
}
```

- Use `sheet(item:)` for editor and quick-entry sheets.
- Sheets own Save/Cancel and call `dismiss()` internally.
- Use a full-screen cover for an active Workout Session.
- Preserve the system edge-swipe back gesture.
- Do not use a tab item as an action button.

## 5. Persistence model

### CloudKit constraints

Every `@Model` record must:

- have a UUID `id`, but never use `@Attribute(.unique)`;
- provide defaults for stored properties where practical;
- avoid nonoptional SwiftData relationships;
- prefer UUID foreign keys for ordered child records;
- include `createdAt`, `updatedAt`, and optional `deletedAt` when soft deletion is needed;
- use raw strings for enums with tolerant decoding to an `.unknown` or safe default;
- avoid relying on CloudKit transaction order.

The app repairs duplicate logical singleton/settings records deterministically by choosing the greatest `updatedAt`, merging safe values, and tombstoning the rest.

### Records

#### Configuration

| Record | Required fields |
|---|---|
| `AppSettingsRecord` | id, createdAt, updatedAt, onboardingCompleted, domainDayCutoffMinutes (180), unitSystem, selectedAppearance, notification settings, iCloud status metadata |
| `NutritionTargetRecord` | id, effectiveFrom, effectiveTo?, calorieDisplayTarget (2400), calorieMinimum (2300), calorieMaximum (2500), proteinMinimumGrams (150), createdAt, updatedAt |
| `CycleAnchorRecord` | id, nextWorkoutTemplateID, firstDueDomainDay, createdAt, updatedAt |

Targets are effective-dated. Completed Nutrition Days snapshot the applicable values.

#### Workout templates

| Record | Required fields |
|---|---|
| `WorkoutTemplateRecord` | id, name, focus, sequenceIndex, recoveryDaysAfter, isArchived, createdAt, updatedAt |
| `ExercisePrescriptionRecord` | id, workoutTemplateID, displayName, orderIndex, workingSetCount, repMinimum, repMaximum, rirMinimum?, rirMaximum?, notes, loadIncrementKg, isOptional, isArchived, createdAt, updatedAt |
| `ExerciseAlternativeRecord` | id, prescriptionID, displayName, orderIndex, isPreferred, createdAt, updatedAt |

`recoveryDaysAfter` seeds as Upper A 0, Lower A 1, Upper B 0, Lower B 2.

#### Workout history

| Record | Required fields |
|---|---|
| `WorkoutSessionRecord` | id, workoutTemplateID?, workoutNameSnapshot, focusSnapshot, sequenceIndexSnapshot, scheduledDomainDay, startedAt, finishedAt, completionDomainDay, startedEarly, note, createdAt, updatedAt, deletedAt? |
| `ExerciseLogRecord` | id, workoutSessionID, prescriptionID?, exerciseNameSnapshot, orderIndex, setCountSnapshot, repMinimumSnapshot, repMaximumSnapshot, notesSnapshot, statusRaw, createdAt, updatedAt |
| `SetLogRecord` | id, exerciseLogID, setNumber, weightKg, repetitions, rir?, statusRaw, note, createdAt, updatedAt |
| `WorkoutDayEventRecord` | id, domainDay, dueWorkoutTemplateID, kindRaw (`missed`, `skipped`), createdAt, updatedAt, deletedAt? |
| `LoadSuggestionRecord` | id, prescriptionID, sourceSessionID, suggestedWeightKg, statusRaw, createdAt, resolvedAt? |

There is no session-level partial status. Exercise and set status may be completed or skipped.

#### Nutrition

| Record | Required fields |
|---|---|
| `FoodPresetRecord` | id, name, caloriesPerBaseServing, proteinGramsPerBaseServing, isFavorite, lastUsedAt?, createdAt, updatedAt, deletedAt? |
| `FoodEntryRecord` | id, domainDay, consumedAt, presetID?, nameSnapshot, caloriesPerBaseServing, proteinPerBaseServing, servingMultiplier, totalCalories, totalProteinGrams, createdAt, updatedAt, deletedAt? |
| `NutritionDayRecord` | id, domainDay, finalizedAt?, calorieDisplayTargetSnapshot, calorieMinimumSnapshot, calorieMaximumSnapshot, proteinMinimumSnapshot, createdAt, updatedAt |

Persist calculated entry totals to preserve export/history, but recompute and overwrite them whenever base values or multiplier change.

#### Care

| Record | Required fields |
|---|---|
| `CareRoutineTemplateRecord` | id, name, categoryRaw, recurrenceKindRaw, recurrencePayload, notificationMinutes, rollsForwardWhenMissed, isArchived, createdAt, updatedAt |
| `CareTaskTemplateRecord` | id, routineTemplateID, label, genericProductRole?, activeIngredient?, instruction?, orderIndex, requirementKindRaw, conditionGroup?, isArchived, createdAt, updatedAt |
| `CareOccurrenceRecord` | id, routineTemplateID?, routineNameSnapshot, dueDomainDay, dueAt, statusRaw, completedAt?, skippedAt?, rolledFromDomainDay?, createdAt, updatedAt |
| `CareTaskCompletionRecord` | id, occurrenceID, taskTemplateID?, labelSnapshot, instructionSnapshot?, statusRaw, selectedVariant?, completedAt?, createdAt, updatedAt |

`recurrencePayload` is a versioned Codable value containing either weekday sets or alternating interval state. Decode unknown versions safely and surface an editor repair state rather than crashing.

#### Measurements and milestones

| Record | Required fields |
|---|---|
| `BodyMeasurementRecord` | id, kindRaw (`weightKg`, `waistCm`), value, measuredAt, domainDay, sourceRaw (`manual`, `postWorkout`), createdAt, updatedAt, deletedAt? |
| `MilestoneRecord` | id, kindRaw, threshold?, relatedEntityID?, earnedAt, acknowledgedAt?, createdAt |

Adherence scores and streaks are derived, not persisted as authoritative data. Cache only if profiling proves necessary; any cache must be disposable and rebuildable.

## 6. DomainDay

`DomainDay` is a value type, comparable and hashable, representing a local civil date after applying the configured cutoff.

```swift
struct DomainDay: Hashable, Comparable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int
}
```

The conversion algorithm:

1. Resolve timestamp in the supplied `Calendar` and `TimeZone`.
2. Subtract `cutoffMinutes` from the timestamp.
3. Extract year/month/day from the shifted timestamp.

Never compute a Domain Day using fixed 24-hour seconds. Use Calendar arithmetic so daylight-saving transitions remain correct.

Inject `AppClock` and Calendar into engines and tests; never read `Date.now` inside domain logic.

## 7. ScheduleEngine

`ScheduleEngine` is a pure Swift value with no SwiftData or SwiftUI imports.

### Inputs

- ordered active Workout Templates;
- Cycle Anchor;
- nondeleted completed Workout Sessions;
- current Domain Day;
- current recovery configuration;
- Workout Day Events.

### Output

```swift
enum WorkoutScheduleState: Equatable, Sendable {
    case due(workoutID: UUID, dueDay: DomainDay, overdueBy: Int)
    case recovery(nextWorkoutID: UUID, eligibleDay: DomainDay, daysRemaining: Int)
    case active(sessionID: UUID)
    case needsRepair(reason: ScheduleRepairReason)
}
```

### Algorithm

1. If an unfinished active session exists, return `.active`.
2. Find the latest nondeleted completed session by `finishedAt`.
3. If none exists, use the Cycle Anchor's next workout and first due day.
4. Otherwise, find the next active template by sequence order.
5. Calculate eligible day as completion Domain Day plus `recoveryDaysAfter + 1` using Calendar day addition.
6. If current day precedes eligible day, return Recovery.
7. Otherwise return Due; elapsed days increase `overdueBy` but never advance the template.

Missed and Skipped events affect adherence/history only. They never advance the cycle.

### Mutations

- **Finish session:** atomically persist session snapshots and sets, then refresh notifications.
- **Start early:** mark session `startedEarly`; finishing uses actual completion day.
- **Delete/edit completed session:** compute a before/after schedule preview, request confirmation, commit in one main-context transaction, then rebuild day events and notifications.
- **Edit cycle order:** validate that sequence indices are contiguous and at least one workout remains.

## 8. Day rollover and occurrence generation

Use one idempotent `DailyReconciler` invoked:

- after onboarding;
- on scene activation;
- when the significant-time-change notification fires;
- after settings/routine edits;
- after historical edits;
- after CloudKit-imported changes become visible.

The reconciler:

1. computes the current Domain Day;
2. creates missing Care Occurrences in a bounded window;
3. expires yesterday’s nonrolling care as missed;
4. rolls missed hair care to today exactly once;
5. records a Missed Workout Day Event if a prior Due Workout day elapsed without a session or explicit skip;
6. ensures only one logical event/occurrence per composite key, repairing duplicates;
7. invokes `NotificationScheduler.reconcile`.

Use stable deterministic notification identifiers derived from kind plus record ID/domain day. Persistence record IDs remain UUIDs.

## 9. AdherenceEngine

The engine consumes Domain Day facts and returns derived values.

### Daily score

Due activities are:

- Due Workout, if eligible that day;
- Nutrition Day finalization;
- morning Care Routine;
- night Care Routine;
- hair Care Routine when due;
- generated post-workout Care Routine when applicable.

`score = completed due activities / total due activities × 100`.

Recovery does not add a denominator item. Skipped and missed count as incomplete. A day with no due activities is “no obligation,” not 0%.

### Streaks

Implement each category as a dedicated rule rather than a generic consecutive-date counter. Recovery neutrality and rolling hair behavior require category-aware eligibility.

The heatmap and streak calculations must be pure, deterministic, and covered with fixtures spanning at least 18 months.

## 10. ProgressionEngine

For each nonoptional exercise in a completed session:

1. require every prescribed working set to be completed;
2. require every set’s repetitions to be at least the snapshotted maximum;
3. find the next weight as `max completed weight + configured load increment`;
4. create or update one pending Load Suggestion for the prescription;
5. never mutate the template until the Routine Owner accepts.

Skipped sets and exercises produce no suggestion.

## 11. NotificationScheduler

Use `UNUserNotificationCenter` and request `.alert`, `.sound`, and `.badge` only after the onboarding explanation. Apple recommends local notifications for user-requested information and allows pending requests to be canceled when conditions change. See [Apple: Scheduling a notification locally](https://developer.apple.com/documentation/UserNotifications/scheduling-a-notification-locally-from-your-app).

### Categories

- `WORKOUT_DUE`: Start, Remind 30 Minutes, Skip Today
- `CARE_DUE`: Done, Remind 30 Minutes, Skip Today
- `EVENING_CHECKIN`: Open Today, Remind 30 Minutes

### Scheduling strategy

- Schedule only the next actionable workout notification.
- Use repeating calendar triggers for stable daily care only when the task content is identical; otherwise schedule bounded one-shot occurrences.
- Hair care always uses the next one-shot occurrence.
- Reconcile and cancel stale identifiers rather than accumulating requests.
- Coalesce night care and unfinished nutrition at 22:00 into Evening Check-in.
- Reschedule after every relevant mutation and app activation.

Notification actions enter through one `NotificationDelegate`, write via the main ModelContext, run the Daily Reconciler, and refresh the interface. A Done action for care must be idempotent.

## 12. iCloud and conflict behavior

Create the ModelContainer once at app root with an explicit private CloudKit configuration. SwiftData automatically maintains a local replica and synchronizes opportunistically; the product must never imply that a change has reached the cloud immediately.

Conflict rules:

- completed history is append-mostly;
- same-record edits resolve by latest `updatedAt`;
- settings use latest `updatedAt`, with deterministic duplicate repair;
- soft-deleted records stay excluded across devices;
- schedule and adherence are always recomputed from reconciled facts;
- if concurrent edits create impossible cycle order or duplicate open sessions, show a Needs Repair screen with a safe suggested resolution.

Settings displays one of: Syncing, Synced recently, iCloud unavailable, or Local only. Do not show a permanent sync indicator elsewhere.

## 13. Seed data

`SeedData` runs exactly once after the persistent store is available. Use a seed version integer, not “database is empty,” so later seed migrations are explicit.

- Workout content comes from `UL_4_Day_Workout_Plan.md`; ignore weekday scheduling.
- Care content comes from `Skincare.md`, normalized to generic roles/actives and stripped of all brands.
- No automatic adapalene progression is seeded.
- Nutrition targets and notification times match the Product Specification.
- The first Cycle Anchor selects Upper A due today.

Seed routines must be represented as typed Swift fixtures and verified against snapshot tests; do not parse Markdown at runtime.

## 14. Export

`CSVExportService` accepts immutable DTOs fetched from SwiftData, escapes RFC 4180 fields, writes UTF-8 with a header row, and returns temporary file URLs for a native share sheet.

- Use stable English machine-readable column headers in v1.
- Include ISO 8601 timestamp, local Domain Day, record ID, and deletion status where relevant.
- Format decimal numbers with `en_US_POSIX` so CSV values use a period regardless of locale.
- Delete temporary export files on the next launch or after a conservative age threshold.
- Verify files in Apple Numbers and with a parser unit test.

## 15. Progress and charts

Use Swift Charts for weight, waist, nutrition, volume, and adherence. Apple’s Charts framework provides native marks, scales, axes, legends, localization, and accessibility support: [Apple: Swift Charts](https://developer.apple.com/documentation/Charts).

- Preaggregate points outside View bodies.
- Downsample only when necessary and never alter totals.
- Weight chart overlays raw observations with a seven-day average.
- Nutrition charts show the target range/threshold as accessible rule marks.
- Exercise chart selection is explicit; do not plot every exercise simultaneously.
- Provide textual summaries for VoiceOver and when charts contain too little data.

## 16. UI performance

- Use stable UUID identity in every List/ForEach.
- Use `LazyVStack`/`LazyHGrid` for history and heatmap content.
- Fetch only the visible/range-relevant history where practical.
- Keep sorting, day bucketing, streak computation, and chart aggregation out of `body`.
- Narrow Observation scope so typing into one set row does not redraw the full session.
- Batch set/session persistence at meaningful checkpoints while retaining in-memory drafts.
- Profile Today, Workout Session, and 52-week heatmap scrolling on the physical iPhone 16 Pro Max.
- Limit custom Liquid Glass elements; Apple warns that too many glass effects or containers can degrade rendering performance. See [Apple: Applying Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views).

## 17. Accessibility and localization

- Use system text styles; no fixed font sizes.
- Minimum 44-by-44-point hit areas.
- Every heatmap cell exposes Domain Day, score, and category summary to VoiceOver.
- Set rows announce set number, weight, reps, RIR, and state in a logical order.
- Use symbols plus text for completed, missed, skipped, warning, and overdue states.
- Support accessibility Dynamic Type without horizontal clipping; dense set rows may reflow vertically.
- Honor Reduce Motion and Reduce Transparency.
- Use `Localizable.xcstrings` from the first commit even though v1 copy is English.
- Never build sentences by concatenating localized fragments.

## 18. Privacy and security

- Store data only in the app sandbox and the Routine Owner’s private CloudKit database.
- No analytics, advertising identifiers, remote logging, or third-party crash reporting.
- OSLog messages must never include food names, notes, body measurements, or skincare state.
- CSV export is an explicit user action and uses the system share sheet.
- Reset All Data must preview scope, require destructive confirmation, delete local records, and allow CloudKit deletion to synchronize.
- Include a privacy manifest reflecting actual API use before distribution.

## 19. Error handling and diagnostics

Define typed errors at service boundaries and translate them to short recovery copy. Never expose CloudKit or SwiftData implementation text directly.

- Recoverable save error: preserve draft, Retry, and Cancel.
- Notification scheduling failure: retain plan and show notification status in Settings.
- Invalid routine recurrence: disable only that occurrence and route to editor repair.
- Duplicate active sessions: let the Routine Owner choose which to resume; keep the other until resolved.
- ModelContainer creation failure: offer Retry and local diagnostics export; never silently create a second store over the first.

Use signposts around Today aggregation, schedule reconciliation, heatmap calculation, and CloudKit-import processing.

## 20. Test strategy

### Unit tests

`ScheduleEngineTests` must cover:

- the exact 0/1/0/2 recovery transitions;
- cycles crossing week, month, and year boundaries;
- missed and skipped days retaining the same workout;
- early sessions;
- long gaps without catch-up;
- 03:00 cutoff boundaries;
- daylight-saving and time-zone changes;
- reordered/deleted templates;
- edited/deleted sessions;
- initial Upper A anchor.

Also test:

- nutrition totals, range boundaries, serving multipliers, and finalization;
- care weekday and alternating 3/4-day recurrences;
- rolling missed hair care exactly once;
- post-workout conditional tasks;
- category streaks and no-obligation heatmap days;
- load suggestions;
- CSV quoting, Unicode, decimal formatting, and row completeness;
- duplicate record repair;
- seed fixtures and seed-version idempotency.

### Persistence and sync tests

- In-memory ModelContainer tests for record mapping and deletes.
- Migration tests from every released schema version.
- Physical-device CloudKit tests with two installations on the same Apple ID.
- Offline create/edit/delete followed by reconnection.
- Concurrent settings edits and duplicate logical records.

### UI tests

- onboarding and notification denial;
- start/finish Upper A and verify Lower A due next day;
- miss, skip, snooze, and start early;
- log/favorite/reuse/edit/delete food;
- finalize and reopen nutrition day;
- complete conditional morning care;
- trigger post-workout care;
- edit plan without changing history;
- export all CSV categories;
- empty, error, and iCloud-unavailable states.

### Visual/accessibility verification

- `#Preview` fixtures for loaded, empty, overdue, recovery, denied-permission, save-error, and large-data states.
- Preview both appearances and representative Dynamic Type sizes, including an accessibility size.
- Run Accessibility Inspector and VoiceOver on device.
- Verify Reduce Motion, Reduce Transparency, Increased Contrast, and grayscale/color-blind distinguishability.

## 21. Implementation order

1. Project shell, design tokens, ModelContainer, and preview fixtures
2. DomainDay and ScheduleEngine with exhaustive unit tests
3. Seed workout/care data and onboarding
4. Today aggregation and Workout Session logging
5. Nutrition logging, presets, targets, and finalization
6. Care occurrences and post-workout conditionals
7. Daily Reconciler and local notifications
8. History, adherence, heatmap, and correction flows
9. Measurements, Progress charts, and milestones
10. Plan editors, settings, iCloud status, and CSV export
11. CloudKit schema initialization/sync verification
12. Accessibility, performance, visual polish, and release checks

Each stage must build cleanly and leave tests green before the next stage begins.
