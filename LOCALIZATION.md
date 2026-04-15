# Localization Strategy

## Current Groundwork

- Added `Localizable.strings` for English and Spanish.
- Added localization helper `L10n.tr(_:)`.
- Routed reminder and crisis-banner copy through localized keys.

## Expansion Plan

1. Externalize all user-facing strings from Swift files.
2. Add localized pluralization for counts in insights and history.
3. Add locale-aware formatting snapshots in UI tests.
4. Add pseudo-localization CI job to catch truncation.
