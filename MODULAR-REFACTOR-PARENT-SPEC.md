# Modular Refactor — Parent Spec

**Status:** Accepted (grilling session, 24 Aug 2026)
**Supersedes:** nothing; refines [MOMENTUM-MODULAR-ARCHITECTURE-SPEC.md](./MOMENTUM-MODULAR-ARCHITECTURE-SPEC.md)
**Child specs:** Hydration v1 definition (open — see §8; blocks Phase F only)

---

## 1. Product posture

- **Public consumer App Store release.** Strangers onboard themselves; no seed-data assumptions about the owner's routines survive into the new-user experience.
- **No accounts, no custom backend — ever.** Private CloudKit sync remains the only durability layer. `ModelContainerFactory`, `CloudAccountStateService`, and iCloud status surfaces stay.
- **Ubiquitous language:** each installation serves exactly one Routine Owner (see [CONTEXT.md](./CONTEXT.md)).

## 2. Launch module roster

| Module | Source | Notes |
|---|---|---|
| **Workout** | Existing domain wrapped | Absorbs the post-workout check-in flow (care occurrence creation stays in this module's UX; weigh-in prompt is **removed**, §4) |
| **Nutrition** | Existing domain wrapped | Unchanged semantics |
| **Personal Care** | Existing Care domain wrapped | Still named "Care" internally and in exports; user-facing Skincare rename is post-validation (spec Phase G) |
| **Hydration** | New | Scope defined by child spec (§8); built only against the new contracts |

**Not modules at launch:**

- **Measurements — cut.** All measurement UI is hidden (Progress charts, logging sheets, post-workout weigh-in). `BodyMeasurementRecord` stays in the SwiftData schema and CSV export; recorded history is preserved untouched. No schema migration.
- **Routines, Sleep, Meditation, Steps, Supplements, Reflection** — post-launch candidates per spec §27.

## 3. Binding architectural decisions

Recorded in ADRs; summarized here for traceability:

1. **[ADR-0001](./docs/adr/0001-specialized-modules-no-universal-habit.md)** — Specialized first-class modules behind a compile-time registry; no universal Habit object; one SwiftData/CloudKit container.
2. **[ADR-0002](./docs/adr/0002-facts-and-projections-for-cross-module-behavior.md)** — Cross-module consequences flow through committed domain facts consumed idempotently at reconciliation time (Strategy A). Post-workout care occurrence keyed by `sourceWorkoutSessionID` is the canonical projection.
3. **Module enablement ships at v1.** Disabled-interval days are ineligible for the category's Category Streak: streaks pause and resume on re-enable, never break, and no missed/skipped events accumulate while disabled. This binds every module's re-enable policy.
4. **Notifications are centralized.** All reminders flow through Core scheduling; module-supplied notification candidates plus Core-owned bundled scenarios (e.g. evening check-in coalescing night-care × open-nutrition, expressed generically by fire-time proximity, not domain knowledge).
5. **Milestones become a Core-level projection** computed over module-emitted facts/summaries (`MilestoneService` unwound from direct cross-domain reads).
6. **DailyThreadFocus survives as a Core-derived rule** over ranked Today contributions (top-ranked contribution determines focus). Its `.reflect` state has no owning module and is deferred to the UX overhaul.

## 4. Deliberate deviations from the modular-architecture spec

- **Measurements demoted** from module (spec §26) to cut feature with retained data (§2 above).
- **Post-workout consequences:** spec §20 proposed splitting the weigh-in out of the workout flow. Decision: the entire check-in stays in the Workout module's completion flow; only the care occurrence crosses a boundary, via fact → projection. The weigh-in prompt is deleted outright (measurements cut).
- **Hydration nudging:** architecture spec §26.1 forbids manipulative repeated nudging. Decision ([HYDRATION-V1-SPEC.md](./HYDRATION-V1-SPEC.md)): progress-proportional reminders are wanted, implemented as deterministic fixed checkpoints (max 3/day, pace-gated, quiet hours 09:00–21:00, suppressed on target reached, all user-editable). The user controls frequency, which preserves the principle's intent.

## 5. Execution plan (Phases A–F)

Full strangler migration per spec §31, with these gates: **each phase ends compiling green with all existing tests passing before the next begins.**

### Phase A — Repository architecture map *(first deliverable)*
Produce `CURRENT-ARCHITECTURE-MAP.md`: dependency map, concrete coupling list, reconciliation entry points, Today aggregation branches, notification/export ownership, cross-domain writes, test coverage inventory. No behavior changes.

### Phase B — Module identity and registry
`ModuleID`, `ModuleMetadata`, compile-time registry, capability protocols (small, split per capability), enabled-module preference persisted in settings, adapters wrapping existing domains (`WorkoutModuleAdapter`, `NutritionModuleAdapter`, `CareModuleAdapter`). Registry carries activation state from day one. Enablement UI deferred (backlog §7).

### Phase C — Shared surfaces consume contributions
Order: Plans → Progress(Insights) → History → Today (last; highest daily-correctness risk). Acceptance: a fake test module appears on every surface without editing surface logic. Surface names stay Today/History/Plans/Progress through migration. DailyThreadFocus re-derived from ranked contributions; milestones recomputed as Core projection.

### Phase D — Reconciliation decentralization
`DailyReconciler` becomes an orchestrator; care repair/roll-forward, workout event back-fill, and occurrence generation move behind module boundaries. Deterministic ordering preserved; scoped failure isolation per spec §35.

### Phase E — Notifications and export decentralization
`ReminderDeriver` domain logic becomes module candidates; categories/identifiers namespaced (`workout.due.<id>`, …); evening check-in moves to Core bundling. `CSVExportService` discovers per-module export definitions; `care.csv` filename and columns unchanged.

### Phase F — Hydration *(gated on child spec)*
Built strictly against contracts proven by Phases B–E. Acceptance: zero hydration-specific branches in Core or any shared surface.

**Measurement cut** executes as a small standalone change alongside Phase B/C (pure presentation removal; no model changes).

## 6. Migration invariants (restated from spec §32, still binding)

History intact · snapshots un-reinterpreted · stable IDs stable · CSV compatibility or explicit versioning · supported CloudKit migrations only · disable ≠ delete · deterministic/idempotent reconciliation.

## 7. Pre-release UX overhaul backlog (separate effort, before public launch)

1. New-user onboarding redesign (current flow assumes the owner's templates; `SeedData` must not shape stranger defaults).
2. Module enablement/re-enable UI placement and flows.
3. Adherence/streak semantics redesign (current blended score and care-collapse preserved through migration only).
4. DailyThreadFocus `.reflect` state — define or remove.
5. User-facing surface renames (Plans→Plan?, Progress→Insights?) and Care→Skincare naming.
6. Evening check-in bundled-notification experience.

## 8. Open items

| Item | Blocks | Resolution path |
|---|---|---|
| ~~Hydration v1 scope~~ | ~~Phase F only~~ | **Resolved** — [HYDRATION-V1-SPEC.md](./HYDRATION-V1-SPEC.md) |
| Measurement module promotion | Nothing (post-launch) | Admission test when justified |
| Routines module | Nothing (post-launch) | Spec §26.1 constraints |

## 9. Risk register (top items)

1. **TodayView rewrite regressions** — mitigated: migrated last, existing reconciler/session tests as guards, fake-module contract tests added in Phase B.
2. **CloudKit schema/migration breakage** — mitigated: no model deletions; UUID-FK design means Phase B–F need no relationship migrations; two-device sync tested per §33.7.
3. **Streak-pause semantics leaking into projections** — Category Streak eligibility must consult module activation history, not just completion facts; called out explicitly in Phase C/D tests.
4. **Coalesced evening reminder regression** — generic fire-time bundling must reproduce current coalescing behavior before old `ReminderDeriver` logic is deleted.
