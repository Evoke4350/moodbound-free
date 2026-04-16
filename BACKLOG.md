# Product Backlog

Moodbound is a personal tool for understanding your own mood patterns.
The math stack is strong; most of these items are about surfacing what
it already computes in ways that are useful to *you*, not to a clinician
or a care system.

Status legend:

- `[ ]` not started
- `[~]` in progress
- `[x]` shipped
- `[-]` deferred / needs product decision

---

## P0 — Make Existing Features Findable

Things the app already has but that are hard to reach or feel unfinished.

### 0.1 Safety Plan should be reachable
- [ ] Add a Safety toolbar button to `HomeView` (next to the Settings
      gear). The plan exists; it just needs a door that's always visible.
- [ ] Remove the severity gate on the "Open Safety Plan" button in
      `InsightsView.warningCard`. The warning card itself stays gated
      (it has nothing meaningful to show when severity is `.none`), but
      the button to reach your own plan shouldn't require the engine to
      flag you first.

### 0.2 Weather card: fix or remove the stub
- [-] The weather impact card on Insights renders as just a title when
      there isn't enough data diversity for the rain/heat comparison.
      Options:
      - **(A)** Remove from Insights, keep in the clinician PDF only.
      - **(B)** Demote to a one-liner on the outlook card.
      - **(C)** Suppress below 7 weather days; show a "still gathering"
        hint when deltas are nil.
- [-] Needs decision: pick A, B, or C.

---

## P1 — Show Me What the Math Found

The engine computes a lot. Most of it surfaces as opaque numbers on
the Insights tab. These items translate engine output into personal,
plain-language observations.

### 1.1 Post-entry feedback
- [ ] After saving an entry, show a brief one-liner before dismissing:
      "Your 7-day outlook shifted from 22% → 28%", or "This tightened
      your confidence interval." If nothing materially changed, just
      confirm "Logged."
- [ ] Source: diff `RiskForecastService` + `ConformalCalibrationService`
      before/after.

### 1.2 Personal pattern stories
- [ ] Turn engine output into "your pattern" sentences on Insights:
      - "When your sleep drops below 6h, your mood tends to shift
        upward ~2 days later." (`DirectionalSignalService`)
      - "Work stress is your strongest mood-lowering trigger."
        (`TriggerAttributionService`)
      - "Your sleep regularity improved from 42 → 68 this month."
        (`DigitalPhenotypeService`)
- [ ] Replace or augment the current generic `InsightNarrativeComposer`
      cards. Follow `SafetyCopyPolicy` for any risk-adjacent language.

### 1.3 "Why this number?" tap-through
- [ ] Each numeric card on Insights (outlook score, concern level,
      change-point probability, drift score) gets a tap-through that
      explains in plain language what it means, what drove it, and
      what would change it.

### 1.4 Month-over-month comparison
- [ ] A card on Insights: "This month vs last month" — avg mood, sleep
      regularity delta, med adherence delta, outlook trend. Two
      `InsightEngine.snapshot` calls, diff the fields.

---

## P2 — Adapt to How I'm Doing

The HMM classifies you into states (depressive, stable, elevated,
unstable). The app can use that to adjust what it shows, not to
diagnose, but to be more relevant.

### 2.1 Contextual Home screen
- [ ] Use the most recent `dominantState` to adjust the copy and
      emphasis on `HomeView`:
      - **Stable**: streak note, maybe a "things look steady" message.
      - **Shifting**: "Your patterns have been shifting — here's what
        your data shows." Link to Insights.
      - **Low energy**: shorter check-in prompt, surface coping
        strategies from the safety plan if the user wrote any.
- [ ] This is a content change, not a layout change.

### 2.2 Optional pattern-shift notification
- [ ] Opt-in local notification when the engine detects a meaningful
      shift (BOCPD change-point, severity transition). Not an alarm —
      just "Your patterns shifted this week. Worth a look?"
- [ ] Max 1 per day. Dismissable. Off by default. Respects Do Not
      Disturb.

---

## P3 — Share with My Doctor

PDF export for bringing to an appointment. Detailed plan exists in
session notes.

### 3.1 Data layer
- [ ] `ClinicianReportService` — snapshot for a date range, delegating
      to existing `InsightEngine`.
- [ ] `ClinicianReportDocument` — `FileDocument` + `Transferable`.

### 3.2 Rendering
- [ ] Three-page PDF via `ImageRenderer` + `UIGraphicsPDFRenderer`.
      Page 1: summary + outlook. Page 2: mood chart + phenotype
      biomarkers. Page 3: triggers, meds, narrative, safety plan.

### 3.3 UI
- [ ] `ClinicianReportView` — range picker, generate, `ShareLink`.
- [ ] Entry point: "Share with Doctor" row in Settings.

### 3.4 Tests
- [ ] Range filtering, insufficient-data guard, render smoke test.

---

## P4 — Make Logging Easier

More entries → better math → better insights. Anything that lowers
the friction of logging compounds everything else.

### 4.1 Home Screen / Lock Screen widget
- [ ] `WidgetKit` + `AppIntent`. Tap a mood face → saves a minimal
      entry. "Add details" deep-links into the full form.

### 4.2 Siri / Shortcuts
- [ ] `AppShortcutsProvider` — "Log my mood" shortcut with a quick
      Siri dialog.

### 4.3 Apple Watch (stretch)
- [-] Simple mood picker on the wrist. Needs scoping.

---

## P5 — Understand the Tool

### 5.1 Data quality card
- [ ] Surface `ModelHealthService` metrics on Insights: entries logged,
      coverage, forecast accuracy, calibration trend. Helps you see
      that more logging → tighter predictions.

### 5.2 Seasonal patterns
- [ ] With 6+ months of data, detect month-level mood patterns and
      surface "historically your mood dips in [month]." Simple
      month-binned comparison, no new service needed.

---

## Resolved / Shipped

- [x] Weather data loss on entry edit (PR #1).
- [x] Stale Open-Meteo code set in rain/clear filter (PR #1).
- [x] Sleet/hail WMO code mismapping (PR #1).
- [x] Reverse geocoder failure canceling weather fetch (PR #1).
- [x] "Unknown" city persisted on geocoder miss (PR #1).
- [x] CI: Tuist installer broken (PR #1).
- [x] CI: coverage floor script always reporting 0% (PR #1).
