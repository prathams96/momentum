# CURRENT-ARCHITECTURE-MAP

**Phase A deliverable** — Modular Refactor (see [MODULAR-REFACTOR-PARENT-SPEC.md](./MODULAR-REFACTOR-PARENT-SPEC.md) §5).
Snapshot of the codebase on 24 Aug 2026 at commit `e70a573`. No behavior changes.

---

## 1. Dependency map

### App entry & shell
| File | Depends on |
|---|---|
| `Momentum/MomentumApp.swift` | `PersistenceBootstrap`: `ModelContainerFactory.makeProduction/localDevelopment/preview`, `SeedData.install`; hosts `AppShell`. |
| `Momentum/App/AppShell.swift` | `@Query AppSettingsRecord` (onboarding gate, appearance); owns `MomentumNotificationDelegate`; `NotificationScheduler().configureCategories()`; `CloudAccountStateService.refresh`; `DailyReconciler.reconcileAndNotify` (appear / scenePhase active / time-zone change via `MaterialTimeZoneChangeStore`); hosts Today/History/Plans/Progress; forwards `WorkoutNotificationRoute` binding. |
| `Momentum/App/AppTab.swift` | Pure enum, no domain deps. |

### Features/Today
| File | Depends on |
|---|---|
| `TodayView.swift` | @Query ×10: settings, anchors, workouts, exercises, sessions, workoutEvents, careOccurrences, foodEntries, nutritionDays, nutritionTargets. Services: `ScheduleProjection.currentDomainDay/evaluate`, `HistoryProjection.facts/streaks/adherenceScore`, `NutritionCalculator`, `NutritionDayService.day/target/finalize/reopen`, `WorkoutSessionStarter.start`, `DailyReconciler.reconcileAndNotify`. Writes food-entry duplicate/delete and duplicate-session repair (`WorkoutSessionRepairService`, in-file). Presents `WorkoutSessionView`, `FoodEntrySheet`, `CareRoutineSheet`. In-file `DailyThreadFocus` enum + thread visualization. |

### Features/History
| File | Depends on |
|---|---|
| `HistoryView.swift` | @Query ×9 (settings, workouts, anchors, sessions, workoutEvents, nutritionDays, foodEntries, careOccurrences, measurements). Soft-deletes/undo for FoodEntry/BodyMeasurement/WorkoutSession. Uses `HistoryProjection`, `HistoryCorrectionProjection.workoutDeletionPreview`, `HistoryCorrectionService.toggleNutritionFinalization/undoCareCompletion`, reconcile after corrections. Presents correction sheets + `HistoryDayDetail`. |
| `HistoryProjection.swift` | Defines `HistoryCategory` (all four domains), `HistoryAdherenceFact`, `HistoryStreakSummary`; `facts(...)` maps workout/nutrition/care records → facts; `adherenceScore` → `AdherenceEngine().dailyScore`; `streaks` → engine's three streak functions. |
| `HistoryHeatmapView.swift` | Heatmap views over score closures; `HistoryStreakSummaryView` branches per category; `HistoryDayRow` reads all record arrays with per-domain label logic. |
| `HistoryDayDetail.swift` | Receives record arrays; four domain sections (workout, nutrition finalize/reopen, care incl. `postWorkout` special case, measurements incl. `postWorkout` source); mutations delegated upward. |
| `HistoryCorrectionProjection.swift` | Read-only previews over `ScheduleProjection`/`ScheduleEngine`; reads cutoff from settings. |
| `HistoryCorrectionService.swift` | Transactional mutations: workout completion rewrite (+reconcile inside txn), nutrition finalize/reopen snapshots, care undo restoring recurrence payload. |
| `HistoryCorrectionSheets.swift` | Sheet destination enums (food/measurement/workout variants); `HistoryBackdateSheet` moves entries across domain days then reconciles. |
| `HistoryWorkoutCompletionSheet.swift` | Completion preview + apply via correction service + reconcile. |

### Features/Nutrition
| File | Depends on |
|---|---|
| `FoodEntrySheet.swift` | Upserts `FoodEntryRecord` + `FoodPresetRecord`; saves; fires reconcile-and-notify. |
| `NutritionDayService.swift` | Effective-dated target lookup; day lookup; finalize/reopen with target snapshots. |

### Features/Care
| File | Depends on |
|---|---|
| `CareRoutineSheet.swift` | Task toggles, occurrence complete/skip/undo, alternating-recurrence advance (duplicates reconciler logic); reconcile-and-notify after every persist. |

### Features/WorkoutSession
| File | Depends on |
|---|---|
| `WorkoutSessionStarter.swift` | Guards open session; inserts session + exercise logs + pre-created set logs; save w/ rollback. |
| `WorkoutSessionView.swift` | Set/exercise status mutations; finish computes `ProgressionEngine().suggestion` → inserts `LoadSuggestionRecord`; stamps finishedAt/completionDomainDay; reconcile-and-notify. **In-file `PostWorkoutCheckInView`**: weigh-in writes `BodyMeasurementRecord(sourceRaw:"postWorkout")` (cross-domain) and `PostWorkoutCareService.ensureOccurrence` creates post-workout `CareOccurrenceRecord` keyed by `sourceWorkoutSessionID`. |

### Features/Plans
| File | Depends on |
|---|---|
| `PlansView.swift` | Three domains in one screen: workout cycle, nutrition targets, care routines. In-file services leak outward: `NutritionPlanService.target/saveTarget` (effective-dated targets), `PlanEditingService.reorderWorkouts/chooseNextWorkout/save` — also used by Progress and Onboarding. Inline editors write prescriptions, alternatives, routine recurrences, task templates. |

### Features/Progress
| File | Depends on |
|---|---|
| `ProgressView.swift` | Widest coupling: @Query ×13. Triggers `MilestoneService.reconcile` via a hash of seven record types. Private `ProgressProjection` re-implements weight trend, waist due check, nutrition points, volume summaries, adherence percentages + three streaks directly against `AdherenceEngine` (duplicating `HistoryProjection`). In-file services: `MeasurementService.save/delete`, `LoadSuggestionService.accept/dismiss` (mutates `ExercisePrescriptionRecord.workingWeightKg`). |

### Features/Onboarding & Settings
| File | Depends on |
|---|---|
| `OnboardingView.swift` | One manual-rollback transaction writing settings gate, effective-dated `NutritionTargetRecord`, `CycleAnchorRecord`, per-routine notification minutes by hard-coded name matching; notification authorization; inline CloudKit account check (container id duplicated vs factory). |
| `SettingsView.swift` | Edits via `SettingsDraft`; shows iCloud/notification status raw fields; save → reconcile; export → `CSVExportSnapshot` + `CSVExportService.export`; reset → `ResetAllDataService.reset` + `SeedData.install` + cancel all reminders. |
| `ResetAllDataService.swift` | Deletes all 20 model types in one save. |

### Momentum/Core (app layer)
| File | Role |
|---|---|
| `SchemaV1.swift` | All 20 `@Model` classes; `AppSettingsRecord.canonical` tie-breaker. Cross-domain field: `CareOccurrenceRecord.sourceWorkoutSessionID`. |
| `DailyReconciler.swift` | Central choke point: settings/cutoff resolution; care repair (duplicate repair, missed-marking, roll-forward once, occurrence + task-snapshot materialization), workout missed-event backfill; single save. `reconcileAndNotify` additionally derives reminders and diffs them into UNUserNotificationCenter, recording scheduling health. Also hosts `completeCareOccurrence` used by notification actions. |
| `MilestoneService.swift` | Derivation across 7 fetched record types; inserts/deletes `MilestoneRecord`. |
| `CloudAccountStateService.swift` | Writes iCloud status fields onto settings. |
| `ModelContainerFactory.swift` | Registers all 20 models; CloudKit config `iCloud.com.pratham.momentum`; local dev + preview stores. |
| `SeedData.swift` | seedVersion-gated seeding/migration (v1/v3/v4). |
| `ReminderDeriver.swift` | Pure reminder derivation: workout-due (settings minute), care-due per pending occurrence (night-care coalesced out when equal to nutrition minute while nutrition open), evening check-in. |
| `NotificationScheduler.swift` | Categories/actions (`WORKOUT_DUE`, `CARE_DUE`, `EVENING_CHECKIN`), reconcile diffing with `momentum.` prefix, 30-min follow-ups, cancel-all. |
| `MomentumNotificationDelegate.swift` | Routes taps/actions: start-workout route, mark-care-done via `DailyReconciler.completeCareOccurrence`, skip-today writes care skip or inserts `WorkoutDayEventRecord(kindRaw:"skipped")` directly (notification layer writing workout history). |
| `CSVExportService.swift` | Snapshot fetches 9 record types; emits `workouts.csv`, `food.csv`, `measurements.csv`, `care.csv`, `adherence.csv` (third independent adherence derivation). Hand-rolled RFC4180 escaping (package encoder unused). |
| `ScheduleProjection.swift` / `PersistedDomainDay.swift` / `MaterialTimeZoneChange.swift` | Record→engine adapter; DomainDay codec; TZ-change detection. |

### Package `Sources/MomentumCore`
`DomainDay` (cutoff-aware day), `ScheduleEngine` (workout cycle state machine), `AdherenceEngine` (dailyScore + 3 streak algorithms), `CareScheduleEngine` (recurrence evaluate/advance/roll-forward), `NutritionCalculator`, `ProgressionEngine`, `RFC4180CSVEncoder` (currently unused by app exporter).

## 2. Concrete coupling list (shared surfaces ↔ domains)

1. **TodayView** queries ten record types across three domains; `dailyThreadFocus` hard-codes priority workout→food→care→reflect; care section matches roles by string (`morning`/`night`/`hair`/`postWorkout`); nutrition evaluates targets inline.
2. **History family**: `HistoryCategory` enumerates the taxonomy; `HistoryProjection.facts` knows each domain's completion semantics; heatmap/streak/day-row views branch per category; `HistoryDayDetail` renders four domain sections with post-workout special cases.
3. **PlansView** owns three domains' editing plus shared services defined in-file (`NutritionPlanService`, `PlanEditingService`) consumed by Progress and Onboarding.
4. **ProgressTabView** queries everything, duplicates adherence/streak computation, triggers milestone reconciliation from a view, defines `MeasurementKind/MeasurementService/LoadSuggestionService` reused elsewhere.
5. **AppShell** plumbs the workout-specific `WorkoutNotificationRoute`.
6. **SettingsDraft** mirrors per-routine minutes into legacy settings fields by hard-coded routine names.
7. Adherence/streak logic exists in three places: `AdherenceEngine` (canonical), `HistoryProjection` wiring, `ProgressProjection` duplicate.

## 3. Reconciliation entry points

`DailyReconciler.reconcileAndNotify` is called from: TodayView (day-change task + refresh after mutations), AppShell (appear/active/TZ change), HistoryView (after every correction/deletion/undo/backdate), HistoryBackdateSheet, HistoryWorkoutCompletionSheet, CareRoutineSheet.persist, FoodEntrySheet.save, WorkoutSessionView.finish + PostWorkoutCheckInView.save, MomentumNotificationDelegate.handle tail, SettingsView.persistSettings.
`DailyReconciler.reconcile` (no notifications) runs inside HistoryCorrectionService transactions.
Other mutation boundaries that save directly: WorkoutSessionStarter, NutritionDayService, NutritionPlanService/PlanEditingService, MilestoneService, CloudAccountStateService, SeedData, ResetAllDataService, plus ~10 direct view saves.

## 4. Today aggregation branches

Sections: dateLine/DailyThread → workoutSection → nutritionSection → activitySection(care) → consistencySection(adherence).
Focus rule: workout when schedule active/due/needsRepair; else food while nutrition unfinalized; else care while any today occurrence pending; else reflect.
Consistency: `HistoryProjection.facts` → heatmap scored with `adherenceScore(category:.all)` + `streaks`.

## 5. Notification/export ownership

- ReminderDeriver produces ≤3 families/day: `workout.<uuid>.<day>`, `care.<occurrenceID>` (night-care coalesced into evening when minutes match and nutrition open), `evening.<day>`. Only future times survive.
- Scheduler categories carry actions: start/remind-30/skip (workout), done/remind-30/skip (care), open-today/remind-30 (evening). Identifiers prefixed `momentum.`.
- Delegate mutates data directly (care complete via reconciler boundary; workout skip event inserted by notification layer).
- CSVExportService: 5 files; adherence.csv computed independently of HistoryProjection.

## 6. Cross-domain writes

1. Workout completion → post-workout `CareOccurrenceRecord` (+task snapshots) keyed by `sourceWorkoutSessionID` (ADR-0002 canonical projection).
2. Workout completion → optional `BodyMeasurementRecord(kindRaw:"weightKg", sourceRaw:"postWorkout")` (weigh-in prompt).
3. Workout flow → `LoadSuggestionRecord`; acceptance later mutates `ExercisePrescriptionRecord.workingWeightKg`.
4. Notification delegate → `WorkoutDayEventRecord(kindRaw:"skipped")`.
5. MilestoneService → cross-domain `MilestoneRecord` writes triggered from Progress view.
6. Care completion → recurrence payload advance, implemented twice (view + reconciler) kept consistent via `recurrencePayloadBeforeCompletion`.

## 7. Test coverage inventory

**Package (`Tests/MomentumCoreTests`, 53 tests)**: ScheduleEngineTests (cycle order/recovery/anchors/repair), AdherenceEngineTests (score weights, streak semantics incl. roll-forward breaks), CareScheduleEngineTests (recurrence cadence/advance/roll-forward/repair), DomainDayTests (cutoff/DST/addition), NutritionCalculatorTests, ProgressionEngineTests, CSVEncoderTests (RFC4180).

**App (`MomentumTests`)**: MomentumAppTests (containers/seeds/starter/reconciler missed-events/duplicate repair/post-workout isolation/reminder identifiers/coalescing/notification routes/duplicate-session repair), CSVExportServiceTests (5 files stable formatting), HistoryCorrectionTransactionTests (atomicity + rollback), HistoryProjectionTests (heatmap window/equal weighting/streaks/previews), SettingsPersistenceTests (draft mirrors/reset/target effective-dating/measurement edits/load suggestions/appearance/weight trend/cloud+TZ decisions), MilestoneServiceTests (idempotency/thresholds/best replacement/acknowledgement).

**UI (`MomentumUITests`)**: launch smoke through onboarding with preview store.

## 8. Settings field usage notes

Dead/legacy fields confirmed: `morningCare/hairCare/eveningCareNotificationMinutes` (write-only mirrors), `calorieTarget/calorieMinimum/calorieMaximum/proteinMinimum` on settings (superseded by effective-dated `NutritionTargetRecord`), `notificationAuthorizationRaw` (never written/read live instead). Live values come from `domainDayCutoffMinutes`, `unitSystemRaw`, `selectedAppearanceRaw`, `workoutNotificationMinutes`, `nutritionReminderMinutes`, `seedVersion`, iCloud status fields, `notificationSchedulingStatusRaw`.

## 9. Refactor observations (input to Phase B)

1. Shared surfaces know every domain — registry-driven contributions are the seam.
2. Reconciliation funnels through one async choke point — module-scoped steps slot in behind it.
3. Adherence derived three ways — consolidate to Core projection over module-provided facts.
4. Services defined inside feature files leak across features — promote to module boundaries.
5. Duplicate care-recurrence-advance implementations must converge on one boundary.
6. Dead schema fields are safe to leave (no migration risk) but must not be extended.
