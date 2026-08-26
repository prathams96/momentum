# Pending Design Rework

**Status:** Superseded by [PRELAUNCH-DESIGN-SPEC.md](./PRELAUNCH-DESIGN-SPEC.md) — all items resolved 25 Aug 2026.
**Source:** [MODULAR-REFACTOR-PARENT-SPEC.md](./MODULAR-REFACTOR-PARENT-SPEC.md) §7 (pre-release UX overhaul backlog), [MOMENTUM-MODULAR-ARCHITECTURE-SPEC.md](./MOMENTUM-MODULAR-ARCHITECTURE-SPEC.md) Phases G–H, and open findings from the 25 Aug 2026 branch review of `feat/modular-refactor-hydration`.
**Constraint:** all of this is *pre-public-launch* work; the migrated behavior it replaces is preserved deliberately through migration only.

---

## 1. New-user onboarding redesign

**Source:** parent spec §7.1
**Problem:** the current onboarding flow assumes the owner's own templates; `SeedData` shapes stranger defaults. A public consumer app cannot ship defaults derived from one person's routines.
**Scope:**
- Redesign onboarding to collect only what a stranger actually needs (or start empty with sensible per-module defaults).
- Guarantee `SeedData` never leaks into the new-user experience (seed only behind explicit restore/dev paths).
- Re-check hydration plan defaults against stranger expectations (2.5 L target, 250/500/750 presets).
**Depends on:** nothing; can start immediately.

## 2. Module enablement / re-enable UI

**Source:** parent spec §5 Phase B ("Enablement UI deferred"), §7.2
**Problem:** enablement is fully persisted (`AppSettingsRecord.enabledModulesRaw`) and the ledger/streak-pause machinery is live, but there is no user-facing way to enable or disable a module.
**Scope:**
- Placement decision: Settings section vs. per-surface empty states.
- Disable flow must state consequences plainly: hidden surfaces, notifications cancelled, history readable, data retained, streak paused (never broken) — resume next day after re-enable.
- Surface the streak "paused" state somewhere visible so pausing isn't mistaken for a bug.
- No retroactive obligations or streak repair for the disabled interval (already guaranteed by the ledger — verify in UI copy).
**Depends on:** ledger already shipped (`ModuleActivationIntervalRecord`, commit `39502ed`). This UI is what will exercise it in production.

## 3. Adherence / streak semantics redesign

**Source:** parent spec §7.3; CONTEXT.md Category Streak definition
**Problem:** the current blended daily score and care-collapse (all care routines weighted as one activity kind per routine) are preserved through migration only. Four categories now exist (workout, nutrition logging, personal care, hydration); the blended percentage no longer matches the product story.
**Scope:**
- Decide per-category adherence presentation (per-module tiles already render dynamically via registry — build on that).
- Retire or redefine `.all` blended score on Today/History heatmaps.
- Resolve care-collapse: count each Care Routine due vs. collapse to day-level completion?
- Define Recovery Day rendering in any new visualization (neutral, never breaks streaks).
**Depends on:** module enablement UI (#2) — pause states need to be visible wherever streaks are.

## 4. DailyThreadFocus `.reflect` state — define or remove

**Source:** parent spec §3.6, §7.4
**Problem:** `.reflect` has no owning module and was explicitly deferred to this overhaul. Current derivation focuses the first *incomplete* ranked contribution rather than the top-ranked contribution (review finding), and TodayView still carries a `"Workout"` title special case in its callout.
**Scope:**
- Rule decision: top-ranked contribution determines focus (spec wording) vs. first-incomplete (current implementation) — pick one and move the logic into Core.
- Give `.reflect` an owner (e.g., a Reflection module post-launch) or remove the stage.
- Remove the workout-string special case when the rule lands in Core.

## 5. User-facing surface renames + Care → Skincare

**Source:** parent spec §7.5; architecture spec Phase G
**Scope:**
- Rename decisions: Plans → Plan? · Progress → Insights? · Care → Skincare/Personal Care.
- Internal/export names stay `care` / `care.csv` (frozen IDs); renames are presentation-only.
- Phase G boundary pass: move remaining Care-specific rules behind the module; preserve hair-care behavior and the post-workout projection.
- Do **not** extract generic Routines in this phase (architecture spec Phase G constraint).

## 6. Evening check-in bundled-notification experience

**Source:** parent spec §7.6; §9.4 risk item
**Problem:** generic fire-time bundling replaced the old coalescing logic mechanically (bundler folds candidates within ±0 min of the evening anchor and hardcodes the "check your … routine" phrasing + care-specific `actionKind` passthrough — review finding).
**Scope:**
- Product design for the bundled evening notification (what it says, what tapping does).
- Generalize the bundler: real proximity window instead of exact-time equality; replace domain-specific `actionKind` folding with a generic candidate-merge contract.

## 7. Architecture cleanups exposed by Hydration (Phase F follow-through)

**Source:** architecture spec step 15 ("Fix abstractions exposed by Hydration"); branch review findings
- Remove residual `.hydration` branches from shared code: `HistoryProjection.adherenceScore` category loop and the `HYDRATION_REMINDER` registration in Core's scheduler should become registry-driven/generic.
- Milestones become a true Core projection over module-emitted facts/summaries: `MilestoneService` still fetches raw workout/nutrition/care records directly; `ModuleFactRecord` substrate exists but has no consumers yet.
- Fake-module-on-every-surface contract test: render Today/Plans/Progress/History with an injected fake module to lock the Phase C acceptance into CI.
- Imperial preset defaults: spec wants 8/16/24 fl oz; ml-canonical rounding currently renders 500 ml as 17 fl oz.
- Consider physical Swift package separation (architecture spec step 18) — only after logical separation settles.

## 8. Deferred feature work (not design-critical, tracked to not lose)

| Item | Source | Gate |
|---|---|---|
| Hydration time-of-day distribution charts | HYDRATION-V1-SPEC non-goals | Post-v1 |
| Backdating hydration entries | HYDRATION-V1-SPEC non-goals | Post-v1 |
| Measurement module promotion | Parent spec §8 | Admission test when justified |
| Routines / Sleep / Meditation / Steps / Supplements / Reflection modules | Parent spec §2, architecture spec Phase H | Post-launch; Routines proves specialized-vs-simple distinction |
| HealthKit / Watch | HYDRATION-V1-SPEC non-goals | Post-v1 |

---

## Suggested order

1. **#2 Enablement UI** — unblocks #3, exercises the shipped ledger, smallest scope.
2. **#7 Cleanups** — mechanical, keeps the architecture honest before more UI lands on top.
3. **#4 DailyThreadFocus rule** — small, needed before Today redesign work.
4. **#3 Adherence semantics** — needs #2 for pause visibility.
5. **#1 Onboarding** — big; gate to launch readiness.
6. **#5 Renames + Phase G**, **#6 Evening check-in** — polish tier.
