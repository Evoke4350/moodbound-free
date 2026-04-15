# Sync Strategy and Conflict Policy

## Goal

Add multi-device sync without data loss and without mutating clinical records silently.

## Recommended Architecture

1. Primary path: CloudKit via SwiftData-backed mirroring.
2. Fallback path: JSON export/import remains as manual recovery.
3. All sync writes are idempotent and event-sourced where possible.

## Conflict Resolution Policy

1. Mood entries are immutable-by-id snapshots with editable fields tracked by `updatedAt`.
2. On conflict:
   - Prefer latest `updatedAt` for scalar fields.
   - Merge relationship events by semantic key:
     - medication adherence: (`timestamp`,`medication`,`taken`)
     - trigger events: (`timestamp`,`trigger`,`intensity`)
3. Never auto-delete conflicting safety-plan/contact records; surface merge UI.

## Safety Constraints

1. Conflicts in safety plan and support contacts must produce a visible merge review state.
2. Never mark reminders enabled on a new device unless explicit local permission is granted.

## Rollout Plan

1. Ship read-only sync shadow mode with logging.
2. Enable write sync for beta users.
3. Add conflict review UI for safety/contact entities.
4. Expand automated migration + merge tests before GA.
