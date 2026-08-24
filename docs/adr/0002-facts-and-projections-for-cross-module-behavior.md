# Cross-module consequences via committed domain facts and reconciliation-time projections

Modules must not mutate one another's records. We decided that a module commits read-only **domain facts** after state changes (e.g. `WorkoutCompleted`), and consumer modules create derived consequences idempotently during reconciliation by scanning stable source facts keyed to the source record ID (Strategy A). The existing post-workout care occurrence — already keyed by `sourceWorkoutSessionID` — becomes the canonical example. We deliberately did **not** build an in-memory event bus as the sole mechanism (durability risk) or a persisted event journal (no current need); the journal may be introduced later only if ordered event processing becomes a real requirement.

## Consequences

- Projections must be idempotent and re-derivable from source facts alone; app restarts and repeated reconciliation passes are safe by construction.
- Facts are statements of committed state, never commands; receiver modules decide what, if anything, to do.
- Notification bundling across modules (e.g. evening check-in) is owned centrally by Core, which coalesces module-supplied reminder candidates by fire time, not by domain knowledge.
