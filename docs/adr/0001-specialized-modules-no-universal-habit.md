# Specialized first-class modules with a compile-time registry — no universal Habit object

Momentum is becoming a consumer app that must scale to new behavior domains without turning into a generic habit tracker. We decided every behavior domain is a first-class module (own models, rules, logging UX, insights) registered in a compile-time registry behind a shared shell (Today / History / Plan / Insights / Settings), and explicitly rejected a universal `Habit` entity or universal recurrence/logging model. Generic schemas accumulate per-domain optional fields until they leak everywhere; specialized modules keep each domain's mechanics honest and let new modules (Hydration was first) be added without teaching Core about them.

## Considered Options

- **Universal Habit/HabitEntry schema** — rejected: false abstraction; module-specific fields inevitably leak into shared models.
- **One SwiftData container per module** — rejected: one iCloud lifecycle, simpler migrations/reset; the single container may hold models owned by separate code modules.
- **Runtime-loaded plugins** — rejected: modules are compile-time app features.

## Consequences

- Core must never contain domain business logic; it knows only *that* a module has something due, logged, configurable, exportable.
- Modules may not import one another; cross-module behavior flows through facts/projections (see ADR-0002).
- Simple repeated behaviors belong to a future lightweight Routines module, not to bespoke modules.
