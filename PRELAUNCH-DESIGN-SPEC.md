# Pre-Launch Design Spec

**Status:** Approved — resolves every open item in [PENDING-DESIGN-REWORK.md](./PENDING-DESIGN-REWORK.md) (grilling session, 25 Aug 2026).
**Sources:** PENDING-DESIGN-REWORK.md, MODULAR-REFACTOR-PARENT-SPEC.md §7, MOMENTUM-MODULAR-ARCHITECTURE-SPEC.md Phases G–H, branch review of `feat/modular-refactor-hydration`.
**Glossary impact:** `CONTEXT.md` updated during this session — **Adherence Day** redefined per-category ("Blended score" added to avoid-list); new **Daily Focus** term added ("Reflect stage" marked avoid).
**Design constraints:** PRODUCT.md and DESIGN.md govern all visual work below; DESIGN.md's Heatmap section is amended by this spec (§3).

---

## 1. Daily Focus rule (was #4)

**Decision:** the focus rule is *first-incomplete*, not top-ranked.

- Move derivation out of `TodayView.dailyThreadStages` into Core as a named, tested rule: focus = first due, incomplete activity in the day's ordered contributions across enabled modules.
- When nothing is incomplete, Today presents the day as complete (see below). There is no terminal "reflect" stage.
- Remove `.reflect` entirely (no owning module; the Reflection-module idea stays in the post-launch backlog).
- Remove the `title == "Workout"` string special case in the callout (`TodayView.swift:110`); callout copy becomes generic: "<Module> needs attention" / "<Title> next".

## 2. Module enablement UI (was #2)

**Decisions:** Settings-only control point; all four modules freely toggleable; no per-surface empty-state entry points; no placeholders for disabled modules.

- A Settings section lists Workout, Nutrition, Personal care, Hydration with toggles writing `enabledModulesRaw` via `ModuleEnablementStore`.
- Footer states each consequence plainly, one sentence each:
  - its surfaces are hidden;
  - its notifications are cancelled;
  - history stays readable and data is retained;
  - its streak pauses (never breaks) and resumes the day after re-enable.
- Disabled modules render nowhere: no Today sections, no Plans blocks, no History categories, no Progress tiles, no CSV/export surprises beyond reading retained data. The tab bar never changes shape.
- No retroactive obligations or streak repair across the disabled interval (already guaranteed by the ledger; verify in UI copy).
- This surface is what exercises `ModuleActivationIntervalRecord` / `ModuleEnablementLedger` in production.

## 3. Adherence presentation (was #3)

**Decisions:** retire `.all`; per-category **rhythm strips** with drill-down heatmaps; each due Care Routine counts separately.

### Rhythm strips

- Progress/History top level shows one compact row per *enabled* category: last 28 days as small day cells, streak count right-aligned, tap opens that category's full 16-week heatmap (existing heatmap component reused per category).
- Cell states, one visual language everywhere (strip, drill-down heatmap, VoiceOver):
  - **complete / partial / missed** — five-step tonal ramp from Momentum Pulse per the Heatmap Rule;
  - **recovery / no obligation** — visually distinct via outline, never confused with missed;
  - **paused (disabled interval)** — dimmed/outlined distinct state; while an interval is open the row label reads **"Paused"** instead of a number; VoiceOver says "paused, not broken".
- A fifth module adds a row, not a screen — strips are registry-driven.

### Scoring semantics

- **Adherence Day** is per-category (CONTEXT.md). No blended score anywhere; `.all` is retired from Today/History.
- Each due Care Routine counts as its own due activity (matches shipped `HistoryProjection.swift:117–120` and the glossary); a day's care streak completes only when all due routines are done (matches `AdherenceEngine.careStreak`). The migration-era "care-collapse" is deleted, not preserved.
- Recovery Days add no workout obligation and never break a streak.

## 4. Onboarding redesign (was #1)

**Decisions:** empty-by-default; example plan opt-in; module enablement inferred from onboarding answers; skipped setup steps are skipped; lazy setup on later enable.

### Flow

1. Default path starts truly empty: `SeedData` never installs for new users. Seed installs only behind explicit paths (below) and dev restore.
2. **Example plan**: an explicit "Start from example plan" choice in the onboarding cycle step, plus a restore path in Settings. Content = current `SeedData` essentially unchanged — it is already stranger-appropriate (templates Upper/Lower A/B; care routines named by active ingredient per the Care Product definition).
3. Choosing the example plan installs seed content; otherwise the owner builds their own (or skips).

### Module inference rules

Onboarding completion derives `enabledModulesRaw`; there is no explicit module checklist:

| Module | Enabled iff |
|---|---|
| Workout | the owner confirms a starting point in the cycle step |
| Nutrition | the owner accepts or edits a Nutrition Target |
| Care | the example plan is chosen **or** at least one care reminder time is kept/set |
| Hydration | always (default-on; zero-config, lazily created, cheap to disable later) |

"Skipped ⇒ off" is deliberate; see the app-level empty state below.

### Setup steps

- Disabled modules' onboarding steps are skipped entirely (no hydration plan, no care reminder pickers, no nutrition target fields).
- Every module creates its plan/defaults lazily on first enable or first surface visit (hydration already does via `fetchOrCreate`; workout/nutrition/care need equivalents).

### Edge cases

- **All modules off**: Today shows one app-level quiet line — "Nothing is being tracked yet." with a Settings link. This is the app-level empty state, not a per-module placeholder.
- **Hydration defaults**: metric locales keep target 2 500 ml, presets 250/500/750 ml; imperial locales present target ~85 fl oz and presets 8/16/24 fl oz. Storage stays ml-canonical; fix the whole-fl-oz rounding artifact (500 ml rendering as 17 fl oz).

## 5. Surface renames (was #5)

**Decisions:** the only rename is visible "Care" strings → **"Personal care"**. "Plans" and "Progress" keep their names.

- Rationale: CONTEXT.md defines the category as Personal Care (which includes hair care); "Skincare" would contradict the glossary. The other tabs' names are accurate as-is.
- Presentation-only: internal IDs, export names (`care`, `care.csv`), and schema stay frozen.
- Applies uniformly: Today section header, History category title, heatmap labels, milestone title, Plans headers, nav titles, Settings section, accessibility strings.
- Phase G boundary work proceeds as specced elsewhere: move remaining Care-specific rules behind the module, preserve hair-care behavior and the post-workout projection, do **not** extract generic Routines.

## 6. Evening check-in notification (was #6)

**Decisions:** one notification max per evening; generic candidate-merge contract; tap routes to Today.

- **Merge contract**: each enabled module contributes reminder candidates carrying its own sentence fragment and an optional deep-link payload. Domain-specific folding ("check your … routine", `actionKind: "careDue"` passthrough) is deleted.
- **Fire time**: the *earliest* merged candidate within a **±30 min** proximity window — never later than any folded candidate's own reminder.
- **Copy**: title "Evening check-in"; body is the concatenation of contributed fragments, e.g. "Finish logging today's food. Complete Night care."
- **Tap**: opens Today, focused on the highest-priority incomplete item among merged candidates. No direct-to-sheet deep links from notifications (fragile cold-start behavior); the payload exists for future refinement.

## 7. Architecture cleanups (was #7)

Unchanged from the pending doc except where decided above:

- Registry-drive the residual `.hydration` branches (`HistoryProjection.adherenceScore`, `HYDRATION_REMINDER` registration).
- Milestones become a true Core projection over module-emitted facts/summaries (`ModuleFactRecord` gains consumers).
- Fake-module-on-every-surface contract test locks Phase C acceptance into CI (must respect enablement: a disabled fake module renders nowhere).
- Imperial preset defaults per §4 above.
- Physical Swift package separation remains deferred until logical separation settles.

## Work order

1. **§1 Daily Focus rule** — tiny; unblocks Today work; kills `.reflect`.
2. **§2 Enablement UI** — exercises the ledger; onboarding consumes it later (§4).
3. **§3 Adherence presentation** — needs §2's ledger for pause states.
4. **§7 Cleanups** — mechanical; keeps architecture honest before more UI lands.
5. **§4 Onboarding redesign** — biggest item; consumes §2/§3 decisions.
6. **§6 Evening check-in**, then **§5 Renames** — polish tier.

## Deferred (unchanged)

Hydration distribution charts · hydration backdating · measurement module promotion · Routines/Sleep/Meditation/Steps/Supplements/Reflection modules · HealthKit/Watch — all gated per PENDING-DESIGN-REWORK.md §8.
