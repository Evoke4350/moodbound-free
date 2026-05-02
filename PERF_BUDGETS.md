# Performance Budgets

## Baseline Targets

- Cold launch to first interactive frame: <= 1.8s on recent devices.
- Tab switch latency: <= 150ms p95.
- New entry save action: <= 120ms p95 local persistence.
- History chart render: <= 250ms with 365 entries.
- Insights snapshot computation: <= 40ms for 365 entries.
- Life chart service build: <= 50ms for 365 entries.
- Life chart canvas render: <= 200ms for 365 days.

## Measurement Commands

1. UI launch timing:
   - Use `xcodebuild test` with UI launch test durations.
2. Runtime profiling:
   - Instruments Time Profiler on `HomeView`, `HistoryView`, and `InsightsView`.
3. Memory:
   - Track app RSS at idle and after 500-entry dataset load.

## Current Baseline (2026-04-12)

- UI smoke test launch passed on iPhone 16 simulator in ~3-5s runner context.
- Unit-level insight calculations and persistence operations execute within milliseconds in tests.
- Automated perf tests (`PerformanceBudgetTests`) on iPhone 16 simulator:
  - Feature materialization for 365 entries: ~84ms average.
  - Risk forecast over 365-entry vectors: ~3ms average.
- Automated perf tests (`LifeChartRenderTests`) on iPhone 17 Pro simulator:
  - Life chart service build for 365 entries: ~2.4ms average.
  - Life chart canvas render for 365 days: ~0.18ms average.

## Next Required Pass

1. Capture physical-device timings.
2. Capture p95 from repeated automated runs.
3. Fail CI when launch regression exceeds 20% from baseline.
