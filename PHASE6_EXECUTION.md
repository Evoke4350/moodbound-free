# Phase 6 Execution Spec

## Purpose

Implement a differentiated intelligence layer that is:

1. Personalized per user.
2. Uncertainty-aware.
3. Safety-policy constrained.
4. Fully test-gated.

## Global Delivery Rules

1. No model output reaches UI unless confidence and evidence are present.
2. No causal language is shown as diagnosis or certainty.
3. Every new service ships with unit tests + synthetic backtests.
4. Every safety-facing string passes `SafetyCopyPolicy`.

## Canonical Data Contracts

```swift
struct TemporalFeatureVector {
    let timestamp: Date
    let moodLevel: Double
    let sleepHours: Double
    let energy: Double
    let anxiety: Double
    let irritability: Double
    let medAdherenceRate7d: Double?
    let triggerLoad7d: Double?
    let volatility7d: Double?
    let circadianDrift7d: Double?
}

struct ModelEvidence {
    let windowStart: Date
    let windowEnd: Date
    let signals: [String]
}

struct ProbabilisticScore {
    let value: Double            // 0...1
    let ciLow: Double            // 0...1
    let ciHigh: Double           // 0...1
    let calibrationError: Double // e.g. ECE
}
```

## Build Sequence

## Step 0: Data Foundation

### Deliverables
- `FeatureStoreService` to materialize temporal vectors from local records.
- Stable feature schema versioning (`featureSchemaVersion`).

### Test Gates
- Unit: each feature component calculation.
- Regression: schema version mismatch handling.

### Exit Criteria
- Deterministic feature vectors for identical input data.

## Step 1: Personalized Latent-State Model

### Deliverables
- On-device HMM/state-space service (`LatentStateService`).
- States: `depressive`, `stable`, `elevated`, `unstable`.

### Data Contract
- Input: `[TemporalFeatureVector]`.
- Output: per-day posterior over latent states.

### Test Gates
- Unit: forward-backward normalization and transition constraints.
- Synthetic backtest: recover known hidden states on generated data.

### Exit Criteria
- Posterior probabilities sum to 1.
- Transition smoothing reduces false state flips vs baseline heuristic.

## Step 2: Change-Point Detection

### Deliverables
- `ChangePointService` (CUSUM/Bayesian online change-point).

### Data Contract
- Input: sequential mood/sleep/energy features.
- Output: change events with score and timestamp.

### Test Gates
- Unit: known shift detection on synthetic series.
- False-positive test on stationary series.

### Exit Criteria
- Meets precision/recall threshold on synthetic benchmark.

## Step 3: Uncertainty-Aware Forecasting

### Deliverables
- `RiskForecastService` (7d risk forecast + confidence interval).

### Data Contract
- Output: `ProbabilisticScore`.

### Test Gates
- Calibration tests (ECE/Brier score).
- Reliability curves from replay dataset.

### Exit Criteria
- CI width and ECE within agreed budgets.

## Step 4: Bayesian Safety Risk Engine

### Deliverables
- `BayesianSafetyEngine` updating priors with new entries.
- Severity mapping from posterior risk.

### Data Contract
- Input: latent state posterior + change points + adherence deltas.
- Output: severity + posterior risk + evidence.

### Test Gates
- Unit: monotonic risk behavior for worsening signals.
- Safety policy tests: no high severity without evidence payload.

### Exit Criteria
- Deterministic severity mapping and auditability.

## Step 5: Causal Signal Probes

### Deliverables
- `DirectionalSignalService` using lagged directional checks.

### Data Contract
- Output: directional hints with confidence and caveat flags.

### Test Gates
- Unit: detects known lagged synthetic relationships.
- Guardrail tests: always includes “non-diagnostic” caveat.

### Exit Criteria
- Directional probes are never presented as causal certainty.

## Step 6: Trigger Attribution Ranking

### Deliverables
- `TriggerAttributionService` ranking likely contributors.

### Data Contract
- Input: trigger events + feature windows.
- Output: ranked triggers with attribution confidence + evidence window.

### Test Gates
- Unit: rank stability under minor noise.
- Backtest: top-k attribution hit-rate on synthetic labelled sets.

### Exit Criteria
- Attribution list includes confidence and time window for each item.

## Step 7: Medication Response Trajectories

### Deliverables
- `MedicationTrajectoryService` for short/medium window response.

### Data Contract
- Output: per-medication delta trend + uncertainty.

### Test Gates
- Unit: trend detection on controlled synthetic patterns.
- Bias checks for sparse data.

### Exit Criteria
- No response claim shown when data support is insufficient.

## Step 8: Adaptive Questioning Engine

### Deliverables
- `AdaptiveCheckinService` chooses next best question by expected information gain.

### Data Contract
- Input: current uncertainty profile.
- Output: prioritized optional prompts for next check-in.

### Test Gates
- Unit: prompt selection prioritizes highest entropy gap.
- UX tests: prompts remain bounded and non-overwhelming.

### Exit Criteria
- Reduced uncertainty over repeated sessions in simulation.

## Step 9: Policy-Constrained Narrative Layer

### Deliverables
- `InsightNarrativeComposer` using only approved templates and evidence slots.

### Data Contract
- Input: scored outputs + evidence + confidence.
- Output: user-facing narrative cards.

### Test Gates
- Snapshot tests for all severity levels.
- Guardrail tests against prohibited phrasing.

### Exit Criteria
- Every narrative includes confidence and evidence span.

## Step 10: Drift and Quality Monitoring

### Deliverables
- `ModelHealthService` (drift score, calibration error, stale-model alert).

### Data Contract
- Output: health status and re-baseline suggestion.

### Test Gates
- Unit: drift detector sensitivity.
- Integration: stale-model warnings after threshold duration.

### Exit Criteria
- Health status is visible in Dev Tools and logged.

## Step 11: Digital Phenotype Cards

### Deliverables
- New cards for sleep regularity, activation slope, recovery half-life.

### Data Contract
- Each card includes metric value, uncertainty, and interpretation band.

### Test Gates
- Unit: metric calculations.
- UI tests: cards visible and accessible on compact/regular layouts.

### Exit Criteria
- Cards degrade gracefully to “insufficient data.”

## Step 12: Validation and Release Gates

### Deliverables
- Offline replay suite for entire pipeline.
- Clinical language review package for narratives.

### Test Gates
- End-to-end replay tests with locked expected outputs.
- Safety review checklist all green.

### Exit Criteria
- Phase 6 marked complete only after replay + policy + accessibility + perf gates pass.

## Dependencies Matrix

1. Step 0 is prerequisite for all.
2. Steps 1-3 must complete before Step 4.
3. Steps 5-7 depend on Step 0 and can run in parallel.
4. Step 8 depends on Step 3 uncertainty output.
5. Step 9 depends on Steps 4-8 outputs.
6. Steps 10-12 finalize quality and release readiness.

## Minimal Sprint Slicing

1. Sprint A: Steps 0-2.
2. Sprint B: Steps 3-4.
3. Sprint C: Steps 5-7.
4. Sprint D: Steps 8-9.
5. Sprint E: Steps 10-12.
