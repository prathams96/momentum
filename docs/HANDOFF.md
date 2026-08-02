# Momentum Implementation Handoff

## Objective

Implement the native iOS app defined by this repository’s specification package. The product decisions are settled; implementation should not substitute a weekly workout calendar, introduce automatic health recommendations, add third-party services, or generalize the app for multiple users.

## Read in this order

1. [`PRODUCT.md`](../PRODUCT.md) — audience, purpose, personality, and product principles
2. [`CONTEXT.md`](../CONTEXT.md) — canonical domain language
3. [`docs/adr/0001-use-a-continuous-recovery-driven-workout-cycle.md`](./adr/0001-use-a-continuous-recovery-driven-workout-cycle.md) — core scheduling decision
4. [`docs/adr/0002-use-swiftdata-with-private-cloudkit-sync.md`](./adr/0002-use-swiftdata-with-private-cloudkit-sync.md) — persistence decision
5. [`docs/PRODUCT-SPEC.md`](./PRODUCT-SPEC.md) — complete functional behavior and acceptance criteria
6. [`docs/TECHNICAL-SPEC.md`](./TECHNICAL-SPEC.md) — architecture, models, algorithms, tests, and build order
7. [`DESIGN.md`](../DESIGN.md) — normative visual system and native interaction rules
8. [`UL_4_Day_Workout_Plan.md`](../UL_4_Day_Workout_Plan.md) — seed exercises only; ignore its weekday schedule
9. [`Skincare.md`](../Skincare.md) — seed care steps only; remove brand names and ignore automatic progression

## Source-of-truth precedence

When documents appear to conflict:

1. Accepted ADRs govern architectural and scheduling decisions.
2. `CONTEXT.md` governs terminology.
3. `PRODUCT-SPEC.md` governs user-visible behavior.
4. `TECHNICAL-SPEC.md` governs implementation structure.
5. `DESIGN.md` governs visual and interaction choices.
6. The original workout and skincare Markdown files provide content only where a newer specification has not superseded them.

Do not silently resolve a genuine contradiction. Record it and request a decision.

## Nonnegotiable behaviors

- The Workout Cycle never resets on Monday.
- Recovery is calculated from the actual completion Domain Day.
- Missed and Skipped Workouts never advance the cycle.
- Finish Workout always completes and advances the session; there is no partial-workout state.
- No catch-up or double-workout recommendation is generated.
- Food is manually named with manually entered calories and protein.
- Care data uses generic product roles/actives, never brands.
- Adapalene frequency never changes automatically.
- Weight is recorded at the gym; there is no weight reminder.
- Recovery Days never break a workout streak.
- Data works offline and syncs through private CloudKit without an app account.
- No v1 non-goal is introduced opportunistically.

## Build discipline

1. Follow the staged implementation order in `TECHNICAL-SPEC.md`.
2. Start with DomainDay and ScheduleEngine tests before building schedule UI.
3. Keep each stage buildable and tests green.
4. Add deterministic Preview fixtures alongside each screen.
5. Use only Apple frameworks unless the specification is amended.
6. Initialize and test the CloudKit development schema before promotion.
7. Test on the physical iPhone 16 Pro Max running iOS 26.0.1.
8. Do not claim completion until every `PRODUCT-SPEC.md` acceptance criterion is demonstrated.

## Required implementation evidence

The final handoff back should include:

- clean build output;
- unit and UI test results;
- screenshots of Today, Recovery, Workout Session, Food Entry, Care Routine, History, Progress, and representative empty/error states in light and dark appearances;
- VoiceOver/Dynamic Type/Reduce Motion/Reduce Transparency verification notes;
- physical-device notification verification;
- two-installation private CloudKit sync verification;
- sample CSV exports opened successfully in Numbers;
- CloudKit schema promotion status;
- any deviations from the specs, each with rationale and explicit approval.

## Definition of done

Momentum is done when it is installed and signed under `com.pratham.momentum`, the complete offline workflow is reliable, notifications remain correct after edits and missed days, private iCloud synchronization is verified, history corrections preserve the right Workout Cycle, the visual system matches `DESIGN.md`, and all acceptance criteria pass on the target device.
