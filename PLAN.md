# Plan

## Phase 1: Reliability Foundation

1. Remove silent persistence failures.
2. Add explicit error messaging for create/edit/delete/sample actions.
3. Add domain validation and reject invalid writes.
4. Ensure production builds do not auto-seed fake data.
5. Add test target and core domain tests.

## Phase 2: Core Domain Completion

1. Structured medication model (name, dose, schedule, adherence history).
2. Trigger/event model beyond note text.
3. Enhanced insight computation service with deterministic rules.
4. Replace heuristic-only UI logic with domain services.

## Phase 3: Safety and Support

1. Safety flag detection policies and severity levels.
2. Safety plan setup/edit workflow.
3. Crisis escalation UX with safe language rules.
4. Care contact actions and guidance pathways.

## Phase 4: Durability and Portability

1. Backup/export/import.
2. Sync strategy (iCloud/CloudKit or backend service).
3. Conflict resolution and data recovery.
4. Migration tests for schema evolution.

## Phase 5: Release Quality

1. Unit + integration + UI tests.
2. Accessibility and localization readiness.
3. Performance budgets and profiling.
4. Observability and release checklist.

## Phase 6: Differentiation and Modeling

1. Personalized temporal state modeling for episode-transition detection.
2. Probabilistic risk scoring with explicit uncertainty calibration.
3. Change-point and multi-signal coupling analysis.
4. Evidence-grounded explainability and policy-constrained safety narratives.
5. Adaptive, information-gain-driven check-in UX.
6. Execution order, contracts, and test gates are defined in `PHASE6_EXECUTION.md`.
