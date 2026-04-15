# Observability and Runbook

## Logging

- App-level non-fatal diagnostics use `AppLogger` (`OSLog` backend).
- Persistence failures, backup failures, and reminder scheduling failures are logged.

## Incident Triage

1. Reproduce with latest TestFlight/internal build.
2. Pull device logs filtered by subsystem `com.moodbound.app`.
3. Classify incident:
   - data integrity
   - safety UX
   - reminder delivery
   - performance regression
4. Apply hotfix path:
   - disable risky feature flag if available
   - ship patch release with migration test coverage

## Recovery Procedures

1. For data corruption reports:
   - export backup from affected device
   - validate JSON payload using `BackupService.importJSON` in staging
2. For reminder failures:
   - verify iOS notification authorization state
   - verify `ReminderSettings` persisted values and scheduled request id
3. For safety messaging concerns:
   - check `SafetyCopyPolicy` output for prohibited language violations

## Metrics to Add in Production

- Crash-free sessions
- Save failure rate
- Backup import/export success rate
- Reminder schedule success rate
- Safety-card display frequency by severity (anonymized)
