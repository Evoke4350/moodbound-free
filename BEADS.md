# Beads

Status legend:

- `[x]` done
- `[~]` in progress
- `[ ]` not started

## Foundation and Integrity

- [x] Add in-repo source-of-truth markdown docs.
- [x] Replace silent `try?` save in New Entry flow.
- [x] Replace silent `try?` save in History delete flow.
- [x] Replace silent `try?` save in Dev Tools sample injection.
- [x] Add user-facing alerts for persistence failures.
- [x] Introduce `MoodEntryValidator` with hard constraints.
- [x] Route create/edit writes through validated paths.
- [x] Route sample-data writes through validated paths.
- [x] Disable production auto-seeding of sample data.
- [x] Add central error logging service (non-fatal diagnostics).

## Tests and Quality Gates

- [x] Add unit test target to Tuist project.
- [x] Add tests for streak logic.
- [x] Add tests for rolling-average logic.
- [x] Add tests for date-window filtering.
- [x] Add tests for validation guardrails.
- [x] Add tests for create/edit/delete persistence integration.
- [x] Add tests for chart selection mapping (nearest entry).
- [x] Add tests for time-travel override behavior.
- [x] Add UI tests for core user flows.
- [x] Add CI gate for tests and coverage threshold.

## Domain and Product Gaps

- [x] Implement structured medication entities and adherence model.
- [x] Implement trigger/entity model for contributing factors.
- [x] Move insight heuristics into domain service layer.
- [x] Implement confidence scoring and explainability payloads.
- [x] Add notification/reminder system.
- [x] Add export/import capability.
- [x] Add backup/restore workflow.
- [~] Add sync strategy and conflict resolution.

## Safety and Clinical UX

- [x] Implement warning severity levels and escalation actions.
- [x] Add safety plan authoring and retrieval flow.
- [x] Add crisis UX with safe copy constraints.
- [x] Add contact/provider action pathways.
- [x] Add language guardrails for high-risk messages.

## Release Hardening

- [~] Accessibility audit (VoiceOver, Dynamic Type, contrast).
- [~] Localization strategy and string externalization.
- [~] Performance profiling and budgets.
- [x] Observability and runbook docs.
- [~] Launch checklist completion.

## Advanced Differentiation (Leapfrog Track)

- [x] Add personalized latent-state modeling (e.g., HMM/state-space) for episode-transition detection.
- [x] Add uncertainty-aware forecasting with calibrated confidence intervals per user.
- [x] Add Bayesian safety risk scoring with posterior updates from new entries.
- [x] Add change-point detection for abrupt regime shifts (sleep/mood/energy coupling).
- [x] Add multi-signal temporal feature store (lags, volatility, circadian drift, adherence deltas).
- [x] Add causal signal probes (Granger-style directional checks + caution flags, not diagnosis).
- [x] Add trigger-attribution ranking with confidence and evidence windows.
- [x] Add medication-response trajectory modeling (short/medium window effect estimates).
- [x] Add on-device model quality monitoring (drift, calibration error, stale-model alerts).
- [x] Add policy-constrained narrative generation with evidence-grounded explanations only.
- [x] Add adaptive questioning engine to request highest-information check-in fields.
- [x] Add digital phenotype summary cards (sleep regularity, activation slope, recovery half-life).
