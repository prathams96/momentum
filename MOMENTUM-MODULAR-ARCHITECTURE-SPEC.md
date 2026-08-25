# Momentum — Modular Architecture Product & Technical Specification

**Document type:** Proposed product architecture and technical boundary specification  
**Status:** Draft for repository assessment and implementation planning  
**Baseline:** Current Momentum implementation documented 5 August 2026  
**Primary audience:** Product owner and code agent / implementation engineer  
**Purpose:** Define a scalable module architecture that preserves Momentum's specialized domain experiences while allowing new modules to be added without turning the product into a generic habit tracker or creating a monolithic feature model.

---

# 1. Executive summary

Momentum should evolve from a fixed set of tightly integrated domains into a **shared application shell with specialized, first-class modules**.

The target architecture is:

```text
┌──────────────────────────────────────────────────────────────┐
│                       MOMENTUM APP                           │
│                  Composition / App Target                    │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                       MOMENTUM CORE                          │
│                                                              │
│ Day semantics · Module registry · Navigation contracts       │
│ Today prioritization · Reconciliation orchestration          │
│ Notifications · Sync infrastructure · Export · Settings      │
│ Shared events/facts · Shared UI contracts                    │
└──────────────────────────────────────────────────────────────┘
           │             │             │             │
           ▼             ▼             ▼             ▼
     ┌──────────┐  ┌───────────┐ ┌──────────┐ ┌───────────┐
     │ Workouts │  │ Hydration │ │ Nutrition│ │ Skincare  │
     └──────────┘  └───────────┘ └──────────┘ └───────────┘
           │             │             │             │
           ▼             ▼             ▼             ▼
     Specialized    Specialized   Specialized   Specialized
     data + UX      data + UX     data + UX     data + UX

            Additional modules:
            Body / Measurements · Routines · Sleep · etc.
```

The central architectural rule is:

> **Shared shell, shared contracts, specialized modules. No universal Habit object.**

A module may use its own models, rules, screens, logging flow, recurrence logic, insights, and history representation.

Momentum Core should know **that a module has something due, logged, configured, exportable, or displayable**. It should not need to understand how hydration, workout sets, skincare steps, or sleep sessions work internally.

---

# 2. Baseline from the current implementation

The current product already contains several useful seams that should be preserved rather than replaced.

The baseline implementation has:

- four shared product surfaces: Today, History, Plans, and Progress;
- centralized Domain Day attribution;
- historical snapshots;
- central reconciliation after meaningful mutations and time changes;
- distinct persisted record groups for Workout, Nutrition, Care, and Progress;
- local-first SwiftData persistence with private CloudKit in production;
- centrally reconciled reminders;
- module-like domain behavior even though the code is not yet explicitly structured as modules.

Relevant current-spec sections:

- §3 Information architecture
- §4 Shared domain rules
- §6 Today
- §7 Workout scheduling and session flow
- §8 Nutrition
- §9 Care
- §10 History
- §11 Plans
- §12 Progress
- §14 Notifications
- §15 Persisted product data
- §16 Error, recovery, and repair behavior
- §21 Planning implications

This proposal should therefore be approached as a **boundary refactor**, not a ground-up rewrite.

---

# 3. Product architecture principle

## 3.1 A module is a behavior domain, not an individual habit

Do not create one module per arbitrary repeated behavior.

A dedicated module is justified when a domain has sufficiently distinct mechanics.

Examples that justify modules:

- Workouts
- Hydration
- Nutrition
- Skincare
- Body / Measurements
- Sleep

Examples that probably do not justify dedicated modules:

- Read for 20 minutes
- Make the bed
- Journal
- Call parents
- Stretch for five minutes
- Take a supplement

Simple repeated behaviors should eventually live inside a lightweight **Routines** module.

## 3.2 Generic underneath only where useful

A module may internally reuse generic infrastructure such as:

- schedules;
- reminders;
- historical snapshots;
- units;
- day attribution;
- progress values;
- export;
- shared status semantics.

The user experience should remain domain-specific.

For example, Hydration should show:

```text
1.6 L of 2.5 L

[ +250 ml ] [ +500 ml ]
```

It should not expose a generic configuration grammar such as:

```text
Habit: Water
Goal type: Numeric
Unit: ml
Threshold: 2500
Recurrence: Daily
```

## 3.3 The shell must feel consistent; logging may be specialized

Shared conventions should remain consistent:

- Due
- In progress
- Completed
- Skipped
- Missed
- Paused
- reminder behavior;
- destructive-action patterns;
- plan editing;
- history access;
- accessibility standards.

Module execution surfaces may differ substantially.

---

# 4. Architecture goals

The refactor should achieve the following.

## G1 — Module isolation

A feature module owns its domain rules and persistence behavior.

Core must not contain Hydration-specific, Workout-specific, Skincare-specific, or similar business logic.

## G2 — Stable shared surfaces

Today, History, Plan, Insights, and Settings remain stable as modules are added.

Adding a module should not require redesigning the application's navigation.

## G3 — No feature-to-feature dependencies

A module must not import or directly mutate another module.

Cross-module behavior must flow through Core-defined facts, events, or projections.

## G4 — Incremental migration

The current app should remain usable throughout the refactor.

Avoid a big-bang rewrite.

## G5 — Historical correctness

Existing snapshot semantics, corrections, exports, and schedule truth must survive the refactor.

## G6 — Local-first behavior

Modules remain usable without an account, notifications, or iCloud.

## G7 — Future module scalability

Adding a new module should require:

1. domain models;
2. module implementation;
3. module registration;
4. any required schema/migration work;
5. module tests.

It should not require adding module-specific conditionals throughout Today, History, Plan, or Insights.

## G8 — Strong compile-time boundaries

Modules should be compile-time application features, not downloadable/runtime plugins.

---

# 5. Non-goals

This architecture does **not** require:

- runtime-loaded Swift plugins;
- App Store downloadable modules;
- one database per module;
- one generic `Habit` entity;
- one universal logging form;
- one universal recurrence model;
- third-party module development;
- server-side module configuration;
- an account system;
- a web backend;
- remote feature code delivery.

---

# 6. Terminology

| Term | Definition |
|---|---|
| **Core** | Shared app-level infrastructure and contracts |
| **Module** | A first-class behavior domain with specialized rules and UX |
| **Module registry** | Compile-time registry of modules available in the app |
| **Enabled module** | A module currently active for the user |
| **Module contribution** | Normalized information a module provides to a shared surface |
| **Module route** | Opaque route that returns control to the owning module |
| **Domain fact** | Read-only statement emitted from a module after committed state change |
| **Projection** | Derived state or cross-module consequence computed from domain facts |
| **Reconciliation** | Deterministic repair and derived-state update pass |
| **Shared surface** | Today, History, Plan, Insights, Settings |
| **Module-private model** | Domain persistence that only the owning module may mutate |

---

# 7. Proposed dependency graph

Recommended logical dependency direction:

```text
MomentumApp
 ├── MomentumCore
 ├── MomentumDesignSystem
 ├── WorkoutFeature
 ├── HydrationFeature
 ├── NutritionFeature
 ├── SkincareFeature
 ├── MeasurementsFeature
 └── RoutinesFeature

MomentumCore
 └── must NOT import feature modules

Feature modules
 ├── may import MomentumCore contracts
 └── may import MomentumDesignSystem

Feature modules
 └── must NOT import one another
```

A future package structure could be:

```text
App/
  MomentumApp/

Core/
  MomentumCore/
  MomentumPersistence/
  MomentumDesignSystem/

Features/
  WorkoutFeature/
  HydrationFeature/
  NutritionFeature/
  SkincareFeature/
  MeasurementsFeature/
  RoutinesFeature/
  SleepFeature/            # future
```

Physical package splitting should happen **after** boundaries are proven in the current repository. Logical boundaries can be introduced first.

---

# 8. Momentum Core responsibilities

Momentum Core should own only cross-cutting behavior.

## 8.1 Day semantics

Core owns:

- current local date/time context;
- Domain Day calculation;
- late-night logging cutoff;
- material time-zone changes;
- attribution previews;
- calendar-safe arithmetic.

Modules receive a Core-generated day context rather than independently calculating day boundaries.

Suggested concept:

```swift
struct DayContext {
    let now: Date
    let civilDate: Date
    let domainDay: DomainDay
    let timeZone: TimeZone
    let cutoff: LocalTime
}
```

Exact types should map to the existing implementation rather than forcing a rewrite.

## 8.2 Module registry

Core defines the contract.

The application composition root registers concrete modules.

Illustrative shape:

```swift
struct ModuleID: Hashable, Codable, Sendable {
    let rawValue: String
}

struct ModuleMetadata: Sendable {
    let id: ModuleID
    let displayName: String
    let shortDescription: String
    let iconName: String
    let defaultSortOrder: Int
}
```

The registry is compile-time and deterministic.

Example:

```text
workout
hydration
nutrition
skincare
measurements
routines
sleep            # future
```

## 8.3 Module enablement

Core owns whether a module is enabled.

Disable semantics:

- hide the module from shared surfaces;
- stop future module notifications;
- preserve module history;
- preserve module plan/configuration unless explicitly deleted;
- stop generating new due obligations where appropriate;
- retain export access to historical records;
- allow later re-enable.

Re-enable semantics:

- restore configuration;
- resume scheduling from a clearly defined module-specific rule;
- do not silently create retroactive obligations for the disabled interval.

Each module must implement its own reactivation policy through the module contract.

## 8.4 Shared navigation contracts

Core owns top-level destinations:

- Today
- History
- Plan
- Insights
- Settings

A module owns all routes below its module boundary.

Core should route through opaque module routes rather than importing feature-specific route enums.

Possible conceptual representation:

```swift
struct ModuleRoute: Hashable, Sendable {
    let moduleID: ModuleID
    let token: String
    let payloadID: UUID?
}
```

A code agent may prefer a stronger typed/type-erased approach. The important constraint is ownership:

> Core transports routes. The module interprets them.

## 8.5 Shared settings

Core owns:

- appearance;
- global units preference where meaningful;
- day cutoff;
- module enablement;
- system notification permission state;
- iCloud/sync status;
- export entry point;
- privacy/support links;
- global reset.

A module owns settings specific to its own domain.

---

# 9. Module contract

Every module must provide a standard set of capabilities to Core.

The exact Swift protocol should be designed after mapping current repository types. The following is a behavioral contract, not mandatory syntax.

```swift
protocol MomentumModule {
    var metadata: ModuleMetadata { get }

    func activationState() -> ModuleActivationState

    func onboardingContribution(
        context: OnboardingContext
    ) -> ModuleOnboardingContribution?

    func todayContributions(
        context: DayContext
    ) async throws -> [TodayContribution]

    func historyContribution(
        day: DomainDay
    ) async throws -> HistoryDayContribution?

    func planContribution() -> PlanContribution

    func insightContributions(
        range: DateInterval
    ) async throws -> [InsightContribution]

    func notificationCandidates(
        context: DayContext
    ) async throws -> [NotificationCandidate]

    func exportDefinitions() -> [ModuleExportDefinition]

    func reconcile(
        context: ReconciliationContext
    ) async throws -> ModuleReconciliationResult

    func handle(
        action: ModuleAction
    ) async throws
}
```

A real implementation may separate these responsibilities into smaller protocols instead of one large protocol.

That is likely preferable.

For example:

```text
MomentumModule
TodayProviding
HistoryProviding
PlanProviding
InsightsProviding
NotificationProviding
ExportProviding
ReconciliationProviding
```

Modules implement only capabilities that apply to them.

---

# 10. Capability-based module contracts

Recommended design: use small capabilities rather than one giant protocol.

Example conceptual structure:

```swift
protocol MomentumModule {
    var metadata: ModuleMetadata { get }
}

protocol TodayProviding {
    func todayContributions(...) async throws -> [TodayContribution]
}

protocol HistoryProviding {
    func historyContribution(...) async throws -> HistoryDayContribution?
}

protocol PlanProviding {
    var planEntry: PlanContribution { get }
}

protocol InsightsProviding {
    func insightContributions(...) async throws -> [InsightContribution]
}

protocol NotificationProviding {
    func notificationCandidates(...) async throws -> [NotificationCandidate]
}

protocol ModuleReconciling {
    func reconcile(...) async throws -> ModuleReconciliationResult
}

protocol ModuleExporting {
    var exportDefinitions: [ModuleExportDefinition] { get }
}
```

The registry can hold type-erased capability adapters.

Benefits:

- Measurements does not need to pretend it has due activities.
- A future Notes/Reflection module does not need fake progression logic.
- Modules remain smaller.
- Core can query capabilities rather than concrete feature types.

---

# 11. Today contribution contract

Today should be the strongest shared composition surface.

A module should return normalized **semantic state**, while retaining control over its specialized content.

Suggested data:

```swift
struct TodayContribution: Identifiable, Sendable {
    let id: String
    let moduleID: ModuleID

    let semanticState: TodaySemanticState
    let title: String
    let summary: String?

    let dueAt: Date?
    let isRequired: Bool

    let progress: ProgressDescriptor?
    let primaryAction: ModuleActionDescriptor
    let secondaryActions: [ModuleActionDescriptor]

    let accessibilitySummary: String
}
```

Suggested semantic states:

```text
active
overdue
dueSoon
dueToday
ongoing
optional
completed
blocked
repairRequired
```

Modules determine their semantic state.

Core determines global ordering.

---

# 12. Today priority engine

The shell must own ordering so modules cannot compete for priority.

## Priority order

1. Active
2. Repair required if it blocks an active/due obligation
3. Overdue required
4. Due soon
5. Due today
6. Ongoing target
7. Optional
8. Completed

Within the same class:

1. earlier due time;
2. user-selected module order if supported;
3. module default order;
4. stable contribution ID.

A module may not submit arbitrary numeric priority values.

This prevents hidden product behavior such as:

```text
Hydration priority = 1000
Workout priority = 900
```

## Due soon

Core should define the global threshold.

Initial recommendation:

```text
due soon = scheduled within two hours
```

This may become configurable later but should initially be one product rule.

---

# 13. Specialized Today cards

The normalized contribution does **not** imply generic visual cards.

Each module may render its own module body while Core controls:

- placement;
- outer spacing;
- accessibility container semantics;
- card-level state treatment;
- primary navigation behavior.

Examples:

## Hydration

```text
Hydration

1.6 L of 2.5 L
██████████░░░░

[ +250 ml ]   [ +500 ml ]
```

## Workout

```text
Workout · Due today

Upper A
7 exercises

[ Start workout ]
```

## Skincare

```text
Evening skincare · 10:00 PM

3 steps
Cleanse · Treatment · Moisturize

[ Start routine ]
```

Core should not attempt to render every module from a generic field/value template.

---

# 14. History contribution contract

History remains day-centric.

For a given Domain Day, each enabled or historically relevant module may provide a section.

Concept:

```swift
struct HistoryDayContribution: Sendable {
    let moduleID: ModuleID
    let title: String
    let status: HistoryStatus?
    let summaryRows: [HistorySummaryRow]
    let detailRoute: ModuleRoute?
    let correctionActions: [ModuleActionDescriptor]
}
```

Core owns:

- day selection;
- module filtering;
- chronology;
- day-level layout;
- shared undo presentation where appropriate.

Modules own:

- domain-specific facts;
- detailed history screens;
- edit/move/delete rules;
- historical snapshots;
- correction consequences.

Historical modules should remain viewable even when currently disabled.

---

# 15. Plan contribution contract

The Plan surface becomes a directory of enabled modules plus module-management controls.

Example:

```text
Plan

Workouts
Upper/Lower · Upper A next
>

Hydration
2.5 L daily
>

Skincare
Morning + Evening
>

Nutrition
2,300–2,500 kcal · 150 g protein
>
```

Each module provides:

```swift
struct PlanContribution {
    let moduleID: ModuleID
    let title: String
    let summary: String
    let destination: ModuleRoute
}
```

Core does not understand the internal editor.

---

# 16. Insights contribution contract

Modules should provide complete insight cards or descriptors rather than Core calculating domain metrics.

Examples:

### Workout

- workout consistency;
- exercise performance;
- completed volume;
- progression suggestions.

### Hydration

- average daily intake;
- percentage of target days reached;
- intake distribution by time of day.

### Nutrition

- calorie trends;
- protein trends;
- target days.

### Skincare

- routine consistency;
- morning/evening completion.

### Measurements

- latest weight;
- seven-day average;
- waist trend.

Core owns:

- date-range selection if shared;
- module section ordering;
- overall screen spacing;
- generic empty-state handling where possible.

---

# 17. Persistence architecture

## 17.1 Do not introduce a universal Habit schema

Avoid:

```text
Habit
HabitEntry
HabitGoal
HabitMetric
HabitSchedule
HabitValue
```

with enough optional fields and enums to represent every domain.

This creates false abstraction and eventually leaks module-specific fields into shared models.

## 17.2 Keep module-private models

Recommended conceptual grouping:

```text
Core
  AppSettings
  ModulePreference
  CoreMigrationMetadata
  ...

Workout
  WorkoutTemplate
  ExercisePrescription
  ExerciseAlternative
  WorkoutSession
  ExerciseLog
  SetLog
  MissedWorkoutEvent
  LoadSuggestion
  ...

Hydration
  HydrationPlan
  HydrationEntry
  HydrationDaySnapshot
  ...

Nutrition
  NutritionTarget
  FoodPreset
  FoodEntry
  NutritionDay
  ...

Skincare
  SkincareRoutine
  SkincareStep
  SkincareOccurrence
  SkincareStepCompletion
  ...

Measurements
  BodyMeasurement
  ...

Routines
  RoutineTemplate
  RoutineStep
  RoutineOccurrence
  ...
```

## 17.3 One SwiftData / CloudKit persistence system initially

Do not create a separate model container per module unless a concrete requirement appears.

Reasons:

- one iCloud lifecycle;
- simpler app startup;
- simpler reset;
- simpler migrations;
- easier cross-module read projections;
- less sync-state complexity.

The model container can contain models owned by separate code modules.

## 17.4 Model ownership rule

Only a module may mutate its private records.

Core may:

- query through module-provided repositories/services;
- request reconciliation;
- consume module facts;
- delete all data during explicit global reset through registered module reset handlers.

Another module may not directly mutate them.

---

# 18. Schema and module versioning

Every module should have an explicit internal schema version or migration version.

Concept:

```text
Workout schema: 3
Hydration schema: 1
Nutrition schema: 2
Skincare schema: 2
```

This does not necessarily require persisted integers per row.

It requires a documented mapping between app schema migrations and owning modules.

For each new module release:

- add model types to the application schema;
- initialize CloudKit development schema;
- validate production promotion;
- test migration from every shipped app schema;
- test module enable/disable;
- test two-device sync.

A module being disabled does not remove its model types from the production schema.

---

# 19. Reconciliation architecture

The current implementation has valuable centralized reconciliation semantics.

Preserve the orchestration, but decentralize domain logic.

Target flow:

```text
Core Reconciliation Coordinator
        │
        ├─ 1. Resolve DayContext / timezone state
        │
        ├─ 2. Reconcile enabled modules
        │       ├─ Workout
        │       ├─ Hydration
        │       ├─ Nutrition
        │       ├─ Skincare
        │       └─ ...
        │
        ├─ 3. Run cross-module projections
        │
        ├─ 4. Refresh shared derived summaries
        │
        └─ 5. Reconcile notifications
```

## 19.1 Module reconciliation

Each module owns:

- due-state creation;
- missed-state derivation;
- duplicate repair inside its models;
- recurrence progression;
- domain-specific derived data;
- domain-specific repair states.

## 19.2 Core reconciliation

Core owns:

- orchestration;
- ordering;
- shared DayContext;
- failure reporting;
- notification reconciliation;
- system-level state.

## 19.3 Isolation

If one module contains invalid recurrence data, the whole application should not crash or silently discard other modules.

Core should preserve the current product principle of scoped failures.

---

# 20. Cross-module behavior

Modules must not mutate one another directly.

This matters immediately because the current product has behavior such as:

```text
Workout completed
→ post-workout care can be generated
```

In the new architecture:

```text
Workout module commits WorkoutCompleted fact
        │
        ▼
Core projection/reconciliation layer
        │
        ▼
Skincare module receives read-only source fact
        │
        ▼
Skincare creates an idempotent post-workout routine occurrence
```

## 20.1 Domain facts

Facts describe committed state.

Examples:

```text
WorkoutCompleted
MeasurementLogged
HydrationTargetReached
NutritionDayCompleted
ModuleEnabled
ModuleDisabled
TimeZoneChanged
```

A fact should contain stable source identity.

Example:

```swift
struct WorkoutCompletedFact {
    let sessionID: UUID
    let completedAt: Date
    let domainDay: DomainDay
    let heavySweating: Bool?
    let goingOutdoorsAgain: Bool?
}
```

## 20.2 Fact semantics

Facts are:

- read-only;
- owned by the source module;
- stable enough for projections;
- not commands to another module.

## 20.3 Durable cross-module consequences

For correctness-sensitive consequences, do not rely only on an in-memory event bus.

Two acceptable strategies:

### Strategy A — Reconciliation-derived projection

Receiver scans stable source facts and creates missing derived records idempotently.

Preferred for the initial architecture.

Example:

```text
Skincare reconciliation sees completed workout session X
+ post-workout care preference enabled
+ no occurrence exists for source session X
→ create occurrence keyed to source session X
```

### Strategy B — Persisted event journal

Introduce only if future cases require durable ordered event processing.

Do not build this before there is a real need.

---

# 21. Notifications architecture

Modules own **what should be notified**.

Core owns **how system notifications are scheduled**.

Module produces:

```swift
struct NotificationCandidate {
    let moduleID: ModuleID
    let stableID: String
    let fireDate: Date
    let title: String
    let body: String
    let actionDescriptors: [ModuleActionDescriptor]
}
```

Core handles:

- notification authorization state;
- scheduling;
- cancellation;
- stable identifier namespacing;
- snooze infrastructure;
- application routing when actions are tapped;
- coalescing rules that are truly cross-module.

Notification IDs should be namespaced:

```text
workout.due.<id>
hydration.reminder.<id>
skincare.evening.<id>
```

Disabling a module cancels its future notifications.

---

# 22. Export architecture

Each module owns its own export format.

Core owns:

- export discovery;
- temporary file lifecycle;
- packaging;
- system Share Sheet;
- global export entry point.

Example registrations:

```text
Workout
  workouts.csv
  workout_sets.csv      # future if split

Hydration
  hydration.csv

Nutrition
  food.csv
  nutrition_days.csv    # optional

Skincare
  skincare.csv

Measurements
  measurements.csv
```

Export schemas must contain:

- stable IDs;
- timestamps;
- Domain Day;
- historical snapshots where relevant;
- deletion state where relevant;
- module schema/export version if needed.

---

# 23. Global reset

Core owns the reset flow.

Each module exposes a reset handler.

Reset order should be deterministic.

Concept:

```text
1. Confirm destructive reset
2. Cancel all Momentum notifications
3. Invoke module reset handlers
4. Clear Core preferences/state
5. Reinstall public template definitions
6. Return to onboarding
7. Reconcile
```

Production CloudKit deletion propagation must remain verified.

---

# 24. Module lifecycle

## 24.1 Available

Compiled into the application and registered.

## 24.2 Enabled

Active for the current user.

May contribute to:

- Today;
- Plan;
- Insights;
- notifications;
- onboarding/configuration.

## 24.3 Disabled

- no new routine obligations unless specifically documented;
- no future notifications;
- no Today or Plan contribution;
- history remains readable;
- data retained;
- reactivation supported.

## 24.4 Deprecated

If a future app version removes a user-facing module:

- preserve historical models as long as migration requires;
- expose history/export if reasonable;
- provide migration to replacement module only when semantics are well-defined;
- never silently reinterpret historical data.

---

# 25. Module admission test

A dedicated module should normally satisfy at least **three** of the following.

| Dimension | Question |
|---|---|
| Unique logging | Does it need a domain-specific logging interaction? |
| Unique scheduling | Does it have scheduling semantics beyond a simple recurrence? |
| Unique Today UX | Does useful execution require a specialized card or control? |
| Unique history | Does history need domain-specific interpretation? |
| Unique insights | Are meaningful metrics unique to this domain? |
| Unique configuration | Does setup require specialized domain concepts? |
| Integration potential | Does it naturally connect to HealthKit, Watch, sensors, etc.? |
| Meaningful segment | Is there a clear user segment that values this depth? |

If the behavior is effectively:

> Do X once every day

it belongs in Routines.

---

# 26. Proposed module portfolio

## 26.1 Launch / near-term modules

### Workouts

Status: Existing domain; mature.

Unique mechanics:

- continuous recovery-driven cycle;
- exercise prescriptions;
- sets/reps/load/RIR;
- session lifecycle;
- progression;
- performance history.

### Nutrition

Status: Existing domain; mature enough to wrap.

Unique mechanics:

- food entries;
- calorie range;
- protein minimum;
- daily completion;
- target snapshots.

### Skincare

Status: Derived from current Care domain.

Unique mechanics:

- morning/evening schedules;
- conditional paths;
- ordered steps;
- alternating schedules;
- post-workout care;
- roll-forward behavior.

Near-term migration recommendation:

Wrap current Care behavior as a module before splitting semantics further.

### Body / Measurements

Status: Existing domain.

Unique mechanics:

- numeric observations;
- unit conversion;
- rolling average;
- cadence.

### Hydration

Status: New module.

Recommended as the **first truly new module built against the new architecture**.

Why:

- simple domain model;
- specialized UX;
- no major dependence on existing logic;
- good test of module registration;
- Today contribution;
- notifications;
- History;
- Plan;
- Insights;
- export.

A successful Hydration implementation will prove that the module system is real rather than merely wrappers around legacy features.

### Routines

Status: New/lightweight module.

Purpose:

- repeated behaviors that do not justify first-class modules.

Launch capability should remain intentionally narrow:

- checklist;
- optional duration;
- selected weekdays / daily;
- reminders;
- complete/skip;
- basic consistency.

Do not turn Routines into a universal engine capable of impersonating every first-class module.

---

# 27. Future module candidates

## Sleep

Potential specialized mechanics:

- sleep start/end;
- duration;
- sleep target;
- HealthKit integration;
- sleep regularity;
- bedtime/wake trends.

Admission test: likely passes.

Complexity: high because HealthKit may become central.

## Meditation

Default decision: Routines initially.

Promote to its own module only if the product later needs:

- session timers;
- guided content;
- session taxonomy;
- mindfulness-specific insights;
- Watch integration.

## Steps / Activity

Potential module only after HealthKit integration is justified.

Avoid manual step entry as a primary product experience.

## Supplements

Default decision: Routines.

Do not create a dedicated medical-adherence module without a deliberate health/safety product strategy.

## Hair care

Initially keep with Skincare / Personal Care unless user research demonstrates sufficiently different domain mechanics.

## Reflection

Potential future module if it develops:

- daily notes;
- mood/energy;
- prompts;
- history;
- correlations;
- dedicated Insights.

Do not expose Reflect as a shell stage until this full module exists.

---

# 28. Shared status vocabulary

Modules may have richer internal states, but the shell should understand a limited common vocabulary.

Recommended:

```text
notApplicable
optional
scheduled
dueSoon
due
overdue
active
completed
skipped
missed
paused
blocked
repairRequired
```

Module-specific states remain internal.

Examples:

```text
Workout internal:
recovery
duplicateActiveSession
invalidCycle

Hydration internal:
targetReached
aboveTarget

Skincare internal:
rolledForward
conditionalChoicePending
```

The module maps internal states to shared shell semantics.

---

# 29. Adherence and consistency

Do not require a universal module completion formula.

Each module owns its own consistency semantics.

Examples:

### Workouts

```text
completed due workout opportunities /
all due workout opportunities
```

Recovery remains neutral.

### Hydration

Possible metric:

```text
days target reached /
days with an active hydration plan
```

### Nutrition

Keep separate concepts:

- logging completed;
- calorie target reached;
- protein minimum reached.

### Skincare

```text
completed due routines /
due routines
```

### Measurements

Measurements should generally use cadence rather than daily adherence.

Core may eventually show an overall daily summary, but it should not invent one mathematical score that treats all domains as equivalent.

---

# 30. Module-specific design ownership

Each feature module should ideally own:

```text
Feature/
  Models/
  Services/
  Repositories/
  Reconciliation/
  Views/
  ViewModels/
  Navigation/
  Notifications/
  Export/
  Tests/
```

Shared visual primitives belong in the design system.

Examples:

Shared:

- card container;
- status chip;
- section header;
- progress treatment;
- empty-state component;
- destructive confirmation style;
- chart accessibility wrapper.

Module-owned:

- set logger;
- hydration quick-add buttons;
- skincare path selector;
- calorie/protein entry form;
- weight trend chart semantics.

---

# 31. Migration strategy from the current app

Do not refactor all domains at once.

Use a staged strangler-style migration.

# Phase A — Repository architecture map

Before writing new architecture code, the code agent should map:

- current SwiftData models;
- model-container construction;
- CloudKit configuration;
- reconciliation entry points;
- reminder scheduler;
- Today data aggregation;
- History aggregation;
- Plans screen dependencies;
- Progress screen dependencies;
- navigation state;
- AppSettings ownership;
- service dependencies;
- post-workout Care coupling;
- CSV export ownership.

Deliverable:

```text
CURRENT-ARCHITECTURE-MAP.md
```

No product behavior should change in this phase.

---

# Phase B — Introduce module identity and registry

Create:

- `ModuleID`;
- `ModuleMetadata`;
- module registry;
- enabled-module preference;
- capability definitions.

Wrap existing domains:

```text
WorkoutModuleAdapter
NutritionModuleAdapter
CareModuleAdapter
MeasurementsModuleAdapter
```

These adapters may initially call existing services.

Goal:

> Introduce architectural seams before moving code.

No persistence migration should be required unless necessary for module enablement.

---

# Phase C — Move shared surfaces to contributions

Refactor shared surfaces one at a time.

Recommended order:

1. Plan
2. Insights
3. History
4. Today

Today should be last because it has the greatest daily correctness impact.

Replace logic such as:

```text
if workout...
if nutrition...
if care...
```

with registry-driven module contributions.

Acceptance criterion:

> Adding a fake test module should appear on the shared surface without editing that surface's feature-specific logic.

---

# Phase D — Decentralize reconciliation

Current central reconciliation should become an orchestrator.

Move domain-specific repair/scheduling logic behind module boundaries.

Target:

```text
ReconciliationCoordinator
  → Workout.reconcile
  → Nutrition.reconcile
  → Care/Skincare.reconcile
  → Measurements.reconcile if needed
  → cross-module projections
  → notifications
```

Keep deterministic ordering and existing historical behavior.

---

# Phase E — Decentralize notifications and exports

Convert current hard-coded categories into registered capabilities.

Acceptance:

- enabling/disabling module affects notifications correctly;
- module export appears automatically;
- Core contains no module-specific notification body logic.

---

# Phase F — Build Hydration as the architecture validation module

Do not migrate another legacy feature first.

Build Hydration from scratch using only the new contracts.

Minimum Hydration v1:

### Setup

- target in ml/L or oz;
- two or three quick-add amounts;
- reminder preference.

### Today

- current total;
- target;
- quick add;
- latest entry undo/edit if desired.

### History

- daily total;
- individual entries;
- edit/delete.

### Plan

- target;
- quick-add presets;
- reminders.

### Insights

- average daily intake;
- target-hit days.

### Notifications

- simple scheduled reminder initially;
- no manipulative repeated nudging.

### Export

- stable entry records;
- target snapshot where needed.

If Hydration requires Core to add several hydration-specific branches, the architecture has failed its scalability test.

---

# Phase G — Convert Care into Skincare boundary

Once the module architecture is proven:

- rename user-facing Care to Skincare or Personal Care according to final product naming;
- keep existing data/history intact;
- move Care-specific rules behind the module;
- preserve hair-care behavior initially;
- preserve post-workout projection;
- avoid simultaneously extracting generic Routines.

This phase should prioritize boundary clarity over domain cleanup.

---

# Phase H — Introduce Routines

Build Routines as a deliberately constrained module.

Do not migrate Skincare into Routines.

Routines should support simple repeated behaviors.

This proves the distinction between:

```text
specialized domain module
vs.
simple routine module
```

---

# Phase I — Physical package / target separation

Only after logical dependencies are stable:

- move modules into Swift packages or isolated feature targets;
- enforce import boundaries;
- reduce accidental coupling;
- improve test isolation.

Do not begin the migration by reorganizing every file into packages.

Architecture comes before folder aesthetics.

---

# 32. Migration rules

Throughout refactoring:

1. Existing user history must remain intact.
2. Historical snapshots must not be reinterpreted.
3. Stable record IDs should remain stable.
4. Current CSV exports should either remain compatible or be explicitly versioned.
5. Current workout scheduling behavior must remain unchanged unless separately specified.
6. Current nutrition finalization semantics must remain unchanged unless separately specified.
7. Current CloudKit data must migrate through supported SwiftData schema migrations.
8. Module disablement must not delete data.
9. Module adapters may temporarily bridge old services.
10. New module boundaries should not require rewriting working domain logic without a concrete benefit.

---

# 33. Testing strategy

## 33.1 Core contract tests

Test:

- module registration;
- duplicate module IDs;
- enable/disable;
- contribution discovery;
- routing;
- deterministic ordering;
- notification namespacing;
- reset registration.

## 33.2 Today priority tests

Given contributions from arbitrary modules:

- active outranks overdue;
- overdue outranks due;
- due soon respects global threshold;
- tie-breaks are deterministic;
- disabled modules do not contribute;
- completed items do not displace active items.

Tests should use fake modules, not concrete Workout/Hydration modules.

## 33.3 Module contract tests

Every module receives a reusable contract test suite:

- disabled state emits no current obligations;
- history remains readable when disabled;
- export IDs are stable;
- reconciliation is idempotent;
- notification IDs are namespaced;
- module reset is complete;
- module routes resolve.

## 33.4 Feature tests

Each module owns domain tests.

Example Hydration:

- add 250 ml;
- edit entry;
- delete entry;
- target crossing;
- units;
- target historical snapshot;
- disabled interval;
- re-enable behavior.

## 33.5 Cross-module projection tests

Example:

```text
Workout completion X
→ Skincare post-workout occurrence exists exactly once
```

Test:

- repeated reconciliation;
- app restart;
- source correction;
- source deletion if supported;
- disabled Skincare;
- re-enabled Skincare.

## 33.6 Migration tests

For every shipped schema:

```text
old database
→ upgrade
→ module registry
→ same visible history
→ same current schedule
→ same exports where promised
```

## 33.7 CloudKit tests

- first install;
- second device;
- offline writes;
- reconnect;
- module enable/disable;
- new module records;
- edit/delete;
- reset;
- duplicate repair.

---

# 34. Performance expectations

The architecture must not make every screen query every module's entire database.

Guidelines:

- module contributions should return compact summaries;
- expensive Insights queries should be lazy;
- Today should query only enabled modules;
- History should fetch selected day/range;
- module calculations should use pre-aggregated/efficient queries where necessary;
- reconciliation should remain incremental where possible;
- Core should not serialize all module work unnecessarily if independent operations can safely run concurrently.

Physical-device profiling remains required.

---

# 35. Failure isolation

A broken module should not silently corrupt or hide unrelated modules.

Examples:

### Invalid Skincare recurrence

Expected:

- Skincare surfaces repair state;
- Workout and Hydration remain usable.

### Hydration persistence failure

Expected:

- draft/add flow remains recoverable;
- Today can still show other modules.

### Module contribution failure

Core may show a scoped module error/repair entry rather than failing the entire Today screen.

Fatal shared-store failure remains an app-level failure.

---

# 36. Accessibility requirements

Core-level components must guarantee:

- Dynamic Type;
- 44-point targets;
- non-color-only status;
- semantic ordering;
- shared status terminology;
- reduced motion support.

Modules must supply:

- meaningful accessibility summaries;
- labels for specialized controls;
- text summaries for charts;
- accessible progress descriptions.

Example Hydration:

```text
"Hydration. 1.6 litres of 2.5 litre daily target. 64 percent."
```

---

# 37. App Store / privacy implications

Adding modules should trigger a privacy review.

Each module definition should include:

```text
Data created
Data imported
External APIs
Permissions
Sensitive-data implications
Export behavior
Deletion behavior
Offline behavior
```

Example:

### Hydration

- manually entered intake;
- no new permission;
- local/iCloud only.

### Sleep

Potential:

- HealthKit permission;
- new App Store privacy review;
- source conflict rules;
- read/write permission distinction.

A module must not silently expand data collection.

---

# 38. Module definition template

Every future module should begin with this one-page specification.

```markdown
# <Module Name>

## User problem

## Why this deserves a first-class module

## Module admission-test result

## Setup

## Today contribution

## Primary logging flow

## Completion semantics

## Scheduling / recurrence

## History

## Plan

## Insights

## Notifications

## Export

## Domain models

## Reconciliation rules

## Cross-module facts emitted

## Cross-module facts consumed

## Disable behavior

## Re-enable behavior

## Migration

## Accessibility

## Privacy / permissions

## Non-goals

## Definition of done
```

No module implementation should begin without this definition.

---

# 39. Initial module capability matrix

| Capability | Workout | Hydration | Nutrition | Skincare | Measurements | Routines |
|---|---:|---:|---:|---:|---:|---:|
| Onboarding | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Today | ✓ | ✓ | ✓ | ✓ | Optional | ✓ |
| Specialized logger | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Scheduled obligation | ✓ | Optional | Daily lifecycle | ✓ | Optional cadence | ✓ |
| History | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Plan | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Insights | ✓ | ✓ | ✓ | ✓ | ✓ | Basic |
| Notifications | ✓ | ✓ | ✓ | ✓ | Optional | ✓ |
| Export | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Reconciliation | Heavy | Light | Medium | Heavy | Light | Medium |
| Cross-module facts | Emits | Potential | Potential | Consumes/emits | Emits | Potential |
| External integrations | Future | Future Watch | Future food DB | Low | Future HealthKit | Low |

---

# 40. Architecture acceptance criteria

The modular refactor is successful when all of the following are true.

## Core boundaries

- MomentumCore does not import concrete feature modules.
- Feature modules do not import one another.
- The App composition target is the only place that knows the complete module list.
- No universal Habit model exists.

## Shared surfaces

- Today uses module contributions.
- History uses module contributions.
- Plan uses module contributions.
- Insights uses module contributions.
- Shared surfaces contain no Hydration/Workout/Skincare-specific branches.

## Lifecycle

- modules can be enabled and disabled;
- disabled modules schedule no future notifications;
- disabled module history remains available;
- re-enable behavior is deterministic.

## Persistence

- each module owns its models;
- one module cannot directly mutate another module's models;
- CloudKit migration is verified;
- stable historical IDs remain stable.

## Reconciliation

- Core orchestrates;
- modules reconcile their own domain;
- cross-module consequences are idempotent;
- one module's repair state does not disable unrelated modules.

## Scalability proof

A brand-new Hydration module can be added without modifying feature-specific logic in:

- Today;
- History;
- Plan;
- Insights;
- global notification infrastructure;
- export UI.

Registering models with the app schema and registering the module are expected integration steps.

---

# 41. Repository-assessment questions for the code agent

Before proposing code changes, inspect the repository and answer these questions.

## Architecture

1. Where is the current app composition root?
2. Which types currently act as global coordinators?
3. Which services are concrete singletons/environment objects?
4. Which views directly query SwiftData?
5. Which views directly embed domain-specific aggregation logic?

## Persistence

6. How is the SwiftData schema declared?
7. How is CloudKit configuration initialized?
8. Are model types already grouped by domain?
9. Which relationships cross domain groups?
10. What migrations currently exist?

## Reconciliation

11. Where is central reconciliation implemented?
12. What invokes it?
13. Which steps belong to Workout, Nutrition, Care, and shared Core?
14. Does reconciliation depend on concrete model types across domains?

## Today

15. How is Today's state aggregated?
16. Which domain branches exist?
17. Which calculations should become module contributions?
18. What performance assumptions currently exist?

## History / Plan / Progress

19. Which screens use domain-specific switch/if logic?
20. Which domain sections can be wrapped without moving underlying business logic?
21. Which navigation routes are concrete feature dependencies?

## Notifications

22. Where are notification categories and identifiers defined?
23. How are actions routed?
24. How much of the scheduling code is domain-specific?
25. How is coalescing currently handled?

## Cross-domain coupling

26. How does Workout create post-workout Care?
27. Are there other direct domain-to-domain writes?
28. Which shared models are actually domain-owned but currently globally visible?

## Testing

29. Which existing tests cover Domain Day, reconciliation, workout scheduling, care recurrence, and nutrition finalization?
30. Which tests can act as regression guards during the refactor?

---

# 42. Expected output from the code-agent architecture assessment

Before implementation, the code agent should produce:

```text
1. Current dependency map
2. Concrete domain coupling list
3. Proposed Core contracts
4. Proposed module adapters
5. SwiftData/schema impact
6. Migration risk assessment
7. Reconciliation split plan
8. Shared-surface refactor order
9. File-by-file phased implementation plan
10. Test plan
11. CloudKit validation plan
12. Risks / open decisions
```

The agent should explicitly distinguish:

```text
A. Pure code-boundary refactors
B. Persistence/schema changes
C. User-visible behavior changes
```

The first implementation phase should strongly prefer **A**.

---

# 43. Recommended implementation order

The default order should be:

```text
1. Map current architecture
2. Add Core module contracts
3. Add module registry
4. Wrap existing domains with adapters
5. Add module enablement
6. Refactor Plan contributions
7. Refactor Insights contributions
8. Refactor History contributions
9. Refactor Today contributions
10. Refactor notification registration
11. Refactor export registration
12. Split reconciliation ownership
13. Validate legacy behavior
14. Build Hydration from scratch
15. Fix abstractions exposed by Hydration
16. Convert Care boundary to Skincare
17. Add lightweight Routines
18. Consider physical Swift package separation
```

Do not start by:

- renaming hundreds of files;
- creating many packages;
- rewriting persistence;
- changing workout scheduling;
- changing nutrition completion;
- redesigning adherence;
- adding multiple new modules at once.

---

# 44. Key architectural invariants

These should be treated as non-negotiable unless the spec is deliberately revised.

1. **No universal Habit object.**
2. **Core owns the shell, not domain semantics.**
3. **Modules own their private models.**
4. **Modules do not import one another.**
5. **Cross-module behavior is fact/projection based.**
6. **Today ordering is owned by Core.**
7. **Modules may render specialized logging interfaces.**
8. **One SwiftData/CloudKit system remains the default.**
9. **Disable does not mean delete.**
10. **Historical snapshots remain truthful.**
11. **Reconciliation remains deterministic and idempotent.**
12. **A new module must not require module-specific branches across shared surfaces.**
13. **Physical package separation follows logical separation, not the reverse.**
14. **New modules must pass the admission test.**
15. **Hydration is the validation module for the new architecture.**

---

# 45. Final target state

The intended product and code model is:

```text
                    MOMENTUM
                       │
             ┌─────────┴─────────┐
             │                   │
        SHARED SHELL         SHARED CORE
             │                   │
   Today / History /       Day semantics
   Plan / Insights          Registry
                            Reconciliation
                            Notifications
                            Sync / Export
             │                   │
             └─────────┬─────────┘
                       │
        ┌──────────────┼───────────────────┐
        │              │                   │
        ▼              ▼                   ▼
     Workout        Hydration           Nutrition
      Module          Module              Module
        │              │                   │
        ├──────────────┼───────────────────┤
        │              │                   │
        ▼              ▼                   ▼
    Skincare      Measurements          Routines
      Module          Module              Module

                  Future modules
                     Sleep
                     ...
```

The long-term development test is simple:

> **Can Momentum add a genuinely different behavior domain without teaching Core how that domain works?**

If yes, the module architecture is doing its job.

If adding a module repeatedly forces edits to Core's Today logic, History logic, notification switch statements, export switch statements, or universal data models, the abstraction should be revisited.
