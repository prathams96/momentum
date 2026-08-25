# Hydration v1 — Module Definition

**Status:** Accepted (brainstorm session, 24 Aug 2026)
**Parent:** [MODULAR-REFACTOR-PARENT-SPEC.md](./MODULAR-REFACTOR-PARENT-SPEC.md)
**Architecture:** [MOMENTUM-MODULAR-ARCHITECTURE-SPEC.md](./MOMENTUM-MODULAR-ARCHITECTURE-SPEC.md) §26.1, §38

---

## User problem

People lose track of fluid intake across the day. They need an near-zero-effort way to log drinks and a calm sense of whether they're on pace — not guilt mechanics.

## Why this deserves a first-class module

Distinct logging interaction (one-tap quick-add), distinct Today UX (progress bar + presets), distinct insights (intake averages), and it is the validation module proving the contracts built in Phases B–E.

## Module admission-test result

Passes ≥3: unique logging ✓ · unique Today UX ✓ · unique insights ✓ · integration potential (Watch later) ✓.

## Setup (Plan surface)

- **Hydration Target**: default 2.5 L (metric) / 85 fl oz (imperial), user-editable.
- **Quick-add presets**: three defaults — 250 ml / 500 ml / 750 ml (metric) or 8 / 16 / 24 fl oz (imperial); each slot user-editable.
- **Reminder checkpoints**: on/off master toggle; three editable checkpoint times (defaults 11:00 / 15:00 / 19:00).
- Units follow the global preference; amounts stored internally as millilitres, rendered rounded (whole fl oz).

## Today contribution

```text
Hydration
1.6 L of 2.5 L
██████████░░░░
[ +250 ml ] [ +500 ml ] [ +750 ml ]
Custom…            latest entry: Undo
```

Semantic state maps to `optional` before any entry, `ongoing` while under target, `completed` at/above target. Accessibility summary per architecture spec §36: *"Hydration. 1.6 litres of 2.5 litre daily target. 64 percent."*

## Primary logging flow

One tap on a preset, or Custom… opens a small amount sheet. Both write a Hydration Entry attributed to the current Domain Day via Core's DayContext (late-night cutoff applies). No backdating at v1 — entries always attribute to the current day.

## Completion semantics

No explicit finish action. The day's obligation is satisfied when logged total ≥ target for that day's snapshot. Crossing emits `HydrationTargetReached`; each entry commits `HydrationEntryLogged`. Over-target is allowed with no cap or warning.

## Scheduling / recurrence

Daily lifecycle only; no recurrence machinery. Owes nothing historically — a day short of target simply wasn't completed.

## History

Per Domain Day: total against that day's target snapshot, entry list with time + amount, per-entry edit/delete. Corrections trigger standard reconciliation.

## Plan

Target, quick-add presets, reminder checkpoints — all listed in Setup above; nothing else.

## Insights

- Average daily intake over the selected range.
- Percentage of eligible days with target reached.
Time-of-day distribution charts are deferred post-v1.

## Notifications

Fixed-checkpoint pacing (deliberate deviation from architecture spec §26.1 "no manipulative repeated nudging" — recorded in parent spec §4):

- Three checkpoints per day (user-editable times, defaults 11:00 / 15:00 / 19:00).
- A checkpoint fires **only if** current intake is behind the linear pace toward the day's target at fire time.
- Hard cap 3/day; nothing outside 09:00–21:00 regardless of configured times.
- All suppressed once the target is reached for the day.
- IDs namespaced `hydration.reminder.<day>.<slot>`; snooze uses the shared remind-in-30-minutes action.

## Domain models

- `HydrationPlanRecord` — target, preset amounts, checkpoint times/toggle.
- `HydrationEntryRecord` — amountML, timestamp, domainDay, soft delete (`deletedAt`).
- `HydrationDayRecord` — per-Domain-Day target snapshot.

## Target snapshots

The day's target snapshot is created/reconciled at day start and may track plan edits until the **first entry of that day logs**, after which it freezes. Past days always display against their own snapshot.

## Reconciliation rules

Light. Day rollover: create day record + freeze prior-day snapshot; idempotent. No duplicate repair beyond entry-level undo/edit. Emits no missed/skipped events.

## Cross-module facts

Emitted: `HydrationEntryLogged`, `HydrationTargetReached`, `HydrationPlanEdited`.
Consumed: none.

## Adherence / streak

Fourth category ("hydration") per CONTEXT.md. Category Streak counts consecutive eligible days with target reached; disabled-interval days pause the streak (parent-spec rule). Eligible-day denominator: days with an active hydration plan and enabled module.

## Disable / re-enable behavior

Disable: hidden from surfaces, future notifications cancelled, history readable, data retained, streak paused.
Re-enable: restores configuration; scheduling resumes next day; no retroactive obligations or streak repair for the disabled interval.

## Migration

New model registration in the app schema + CloudKit development schema promotion; no existing data touched.

## Accessibility

Progress described as absolute + percent (see §36 example); preset buttons carry full labels ("Add 250 millilitres"); Dynamic Type and 44-pt targets via design system components.

## Privacy / permissions

Manual entry only; no permissions, external APIs, or imports; local + private iCloud only.

## Non-goals (v1)

Backdating · per-module unit override · HealthKit/Watch · drink-type breakdown · container/bottle tracking · coaching or adaptive targets · intake distribution charts.

## Definition of done

- Appears on Today/History/Plans/Insights purely via registration — zero hydration branches in Core or shared surfaces.
- Contract test suite passes (disabled emits no obligations, idempotent reconcile, stable export IDs, routes resolve).
- Snapshot correctness verified across target edits mid-day and mid-history.
- Checkpoint notification logic tested: pace suppression, cap, quiet hours, disable cancellation.
- Two-device CloudKit sync verified for entries and plan edits.
