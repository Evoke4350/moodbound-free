# Definition of Done

The project is considered finished only when all of the following are true:

## Product

- Core flows (onboarding, check-in, edit, history, insights) are complete.
- Structured medication and trigger tracking are implemented.
- Safety escalation and safety plan workflows are implemented.

## Reliability

- No silent persistence failures remain.
- Invalid data cannot be persisted through supported write paths.
- Migration tests pass for current and previous schema versions.

## Quality

- Unit, integration, and UI test suites are passing.
- Critical domain logic has strong coverage.
- Accessibility checks pass for supported devices.

## Performance and Ops

- Launch and interaction performance budgets are met.
- Crash reporting and failure telemetry are in place.
- Release checklist and rollback plan are documented.
