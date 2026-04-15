# Execution TODO Ledger

Status legend:

- `[x]` complete
- `[~]` in progress
- `[ ]` not started
- `[-]` blocked by product decision

## Reliability and Data Integrity

- [x] Replace silent save failures in create/edit/delete/sample flows.
- [x] Add hard validation guardrails for all write paths.
- [x] Restrict sample seeding to debug builds.
- [x] Add central non-fatal diagnostics logger and route persistence failures through it.
- [x] Add release-mode logging strategy note in docs.

## Tests and Quality Gates

- [x] Unit tests for streak/average/date-window and validator rules.
- [x] Integration tests for create/edit/delete persistence with SwiftData in-memory container.
- [x] Unit tests for chart nearest-point selection mapping.
- [x] Unit tests for time-travel clock override behavior.
- [x] UI smoke tests for core app navigation and new-entry flow.
- [x] CI workflow that generates with Tuist and runs tests.
- [x] CI coverage floor gate and failure on regression.

## Domain Completion

- [x] Introduce structured medication entity (name, dose, schedule metadata).
- [x] Introduce medication adherence event tracking.
- [x] Introduce trigger entity model for contributing factors.
- [x] Link triggers to mood entries.
- [x] Add entry form support for selecting medication adherence and triggers.
- [x] Add history/insight usage of medication and trigger signals.

## Insights and Explainability

- [x] Extract heuristics from views into an insight service.
- [x] Add deterministic warning severity levels.
- [x] Add confidence scoring to generated insights.
- [x] Add explainability payloads shown in UI text.

## Safety UX

- [x] Add safety plan model + create/edit experience.
- [x] Add support contact model + quick actions.
- [x] Add crisis guidance card for highest severity.
- [x] Ensure warning language follows `SAFETY.md` constraints.
- [x] Add copy sanitization policy for high-risk phrases.
- [x] Route severity crisis banners through policy templates.
- [x] Add local reminder configuration in Safety Plan flow.

## Durability and Portability

- [x] Add JSON export of core records.
- [x] Add JSON import with schema validation.
- [x] Add backup/restore flow in app settings/dev tools.
- [x] Persist reminder settings in backup payload.
- [x] Document sync strategy and conflict policy (implementation deferred).

## Release Hardening

- [~] Accessibility pass (labels, hit areas, Dynamic Type sanity).
- [~] Localization groundwork (externalized strings).
- [~] Performance baseline metrics and budgets.
- [x] Observability/runbook docs.
- [~] Launch checklist execution (manual validations pending).

## This Run Target

- [x] Complete all engineering-actionable items that are implementable now without external services or unresolved product policy decisions.

## Phase 6 Modeling Checklist

- [x] Step 0: FeatureStore service + feature schema versioning.
- [x] Step 1: Personalized latent-state model (HMM/state-space).
- [x] Step 2: Change-point detector for regime shifts.
- [x] Step 3: Uncertainty-aware forecast + calibrated confidence intervals.
- [x] Step 4: Bayesian safety risk engine with evidence payloads.
- [x] Step 5: Directional signal probes with non-diagnostic caveats.
- [x] Step 6: Trigger attribution ranking with confidence windows.
- [x] Step 7: Medication response trajectory modeling.
- [x] Step 8: Adaptive questioning via information gain.
- [x] Step 9: Policy-constrained narrative composer.
- [x] Step 10: Drift and calibration monitoring.
- [x] Step 11: Digital phenotype cards.
- [~] Step 12: End-to-end replay + release validation gates (replay automated; manual policy/accessibility/perf gates still pending).
