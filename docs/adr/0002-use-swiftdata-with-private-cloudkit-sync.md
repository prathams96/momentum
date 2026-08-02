# Use SwiftData with private CloudKit sync

Momentum stores records locally with SwiftData and synchronizes them through the Routine Owner’s private CloudKit database, with no app account or custom backend. This preserves offline-first behavior and private Apple-ID-based recovery while accepting CloudKit-compatible schema constraints and the need to treat production schema changes as additive.
