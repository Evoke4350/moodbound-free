# Product Backlog

Prioritized list of features and improvements. The core thesis: the math
stack is excellent but the app doesn't close the loop between "the engine
knows something" and "the user benefits from that knowledge." Most items
below are last-mile delivery for computation that already exists.

Status legend:

- `[ ]` not started
- `[~]` in progress
- `[x]` shipped
- `[-]` deferred / needs product decision

---

## P0 — Safety & Crisis Infrastructure

These are non-negotiable for an app targeting a population with elevated
suicide risk. The math to support them already exists; the delivery
mechanisms do not.

### 0.1 Safety Plan: always-visible access
- [ ] Add Safety toolbar button to `HomeView` (next to Settings gear).
      SF Symbol `cross.case.fill`, tinted red/coral. One tap from the
      default tab on every launch.
- [ ] Remove the `safety.severity != .none` gate in `InsightsView`
      `warningCard` — the "Open Safety Plan" button should always render
      inside the warning card, regardless of severity.
- [ ] Keep the warning card itself gated on severity (it shows evidence,
      severity label, concern level — those are meaningless when severity
      is `.none`). Only the Safety Plan button moves out.

### 0.2 Proactive safety surfacing on Home
- [ ] When `BayesianSafetyEngine.severity` crosses into `.elevated` or
      higher, show a prominent banner at the top of `HomeView`'s scroll
      view — above the check-in prompt — with "Open Safety Plan" and the
      primary support contact's one-tap call button.
- [ ] Banner persists until severity drops back to `.none` or the user
      dismisses it (with a "Dismiss for today" option, not permanent).

### 0.3 Built-in crisis resources
- [ ] Add a `CrisisResources` section to `SafetyPlanView` with
      hard-coded entries: 988 Suicide & Crisis Lifeline (call + text),
      Crisis Text Line (741741), international equivalents keyed by
      `Locale.current.region`. Each with a one-tap call/text button.
- [ ] These are always visible, never gated, never editable by the user
      (they can't accidentally delete 988).

### 0.4 Risk-threshold push notifications
- [ ] Wire `BayesianSafetyEngine.severity` to `UNUserNotificationCenter`.
      When severity crosses from `.none` → `.elevated` (or higher), fire
      a local notification: "Your patterns suggest elevated risk. Tap to
      review your safety plan." Deep-link opens `SafetyPlanView`.
- [ ] Respect a per-session cooldown (max 1 notification per 24h) to
      avoid alarm fatigue.
- [ ] Notification is opt-in, prompted after the user creates their
      first safety plan. Never fire before the user has a plan to open.
- [ ] Follow `SAFETY.md` language constraints: supportive,
      non-diagnostic, non-dismissive.

---

## P1 — Close the Feedback Loop

These turn passive data display into active, personalized feedback at
the moment the user is most engaged.

### 1.1 Post-entry feedback card
- [ ] After saving a new entry, show a brief card before dismissing:
      "Your 7-day outlook moved from 22% → 28%", or "This entry helped
      narrow your confidence interval from ±12% to ±9%."
- [ ] Source: diff the `RiskForecastService` output before and after the
      new entry, and the `ConformalCalibrationService` CI width delta.
- [ ] Keep it to one sentence + one number. Don't overwhelm.
- [ ] If the entry didn't materially change anything, show a simple
      "Logged." confirmation instead.

### 1.2 Personal pattern narratives
- [ ] Replace or augment generic `InsightNarrativeComposer` cards with
      personalized cause-and-effect stories driven by the data the
      engine already computes:
      - `DirectionalSignalService` probes → "When your sleep drops
        below 6h, your mood tends to rise 2 days later (r=0.41)."
      - `TriggerAttributionService` → "Work stress is your strongest
        mood-lowering trigger (effect: -0.8, seen 6 times)."
      - `MedicationTrajectoryService` → "Since starting lithium, your
        average risk dropped from 38% to 21% over 7 days."
      - `DigitalPhenotypeService` → "Your sleep regularity score
        improved from 42 to 68 this month."
- [ ] Use `L10n.tr` for all templates. Follow `SafetyCopyPolicy`
      sanitization for any risk-adjacent language.

### 1.3 Longitudinal comparison
- [ ] "This month vs last month" summary card on Insights: avg mood,
      sleep regularity delta, med adherence delta, forecast trend.
- [ ] Source: two `InsightEngine.snapshot` calls with different date
      windows, diff the fields.

---

## P2 — Phase-Aware UX

The HMM already classifies the user into latent states (depressive,
stable, elevated, unstable). The app should adapt its behavior to match.

### 2.1 Phase-aware Home screen
- [ ] Use `LatentStateDayPosterior.dominantState` (most recent) to
      adjust what `HomeView` emphasizes:
      - **Stable**: streak celebration, psychoeducation tip of the day,
        lower check-in friction (offer quick-log widget).
      - **Prodromal / Elevated / Unstable**: "Here's what happened last
        time this pattern appeared" (pull from `DirectionalSignalService`
        history), proactive safety plan nudge.
      - **Depressive**: supportive copy, low-energy UX (fewer taps to
        log), surface coping strategies from safety plan.
      - **Recovery**: "Day N of recovery. Your pattern suggests ~M more
        days." (from `DigitalPhenotypeService.recoveryHalfLife`).
- [ ] This is a content/copy change, not a layout change. Same Home
      structure, different emphasis text and card ordering.

### 2.2 Adaptive check-in frequency
- [ ] When latent state is stable and forecast risk is low, reduce
      reminder frequency (every 2–3 days instead of daily).
- [ ] When elevated/unstable, increase to daily or twice-daily.
- [ ] Source: `ReminderScheduler` + `BayesianSafetyEngine.severity` +
      `LatentStateDayPosterior`.
- [-] Needs product decision: should the user be able to override?
      (Probably yes — user agency per `SAFETY.md`.)

---

## P3 — Clinician Report PDF

Detailed plan exists separately (see session notes). Summary:

### 3.1 Report data layer
- [ ] `ClinicianReportService.swift` — `snapshot(for: DateInterval,
      context:)` fetching entries via `FetchDescriptor`, delegating to
      `InsightEngine.snapshot(entries:now:)`.
- [ ] `ClinicianReportDocument.swift` — `FileDocument` + `Transferable`.

### 3.2 Report rendering
- [ ] `ClinicianReportPages.swift` — three stateless SwiftUI page views
      rendered via `ImageRenderer` inside `UIGraphicsPDFRenderer`.
- [ ] Page 1: Summary & Safety (severity, key numbers, 7-day outlook
      with conformal CI, change-point + drift scores).
- [ ] Page 2: Trajectory & Latent State (mood chart with HMM overlay,
      phenotype biomarkers, weather impact).
- [ ] Page 3: Triggers, Medication & Narrative (attribution table,
      med trajectories, narrative cards, user's safety plan text +
      support contacts, crisis banner).

### 3.3 Report UI + entry point
- [ ] `ClinicianReportView.swift` — range picker (30/60/90/custom),
      generate button, `ShareLink` on completion.
- [ ] Settings entry: "Share with Clinician" row in a `Reports` section.

### 3.4 Report tests
- [ ] `ClinicianReportServiceTests.swift` — range filtering, insufficient
      data threshold, rendering smoke test.

---

## P4 — Reduce Logging Friction

The #1 failure mode of any mood tracker is the user stops logging.
Better data density directly improves every model in the math stack.

### 4.1 Home Screen / Lock Screen widget
- [ ] `WidgetKit` + `AppIntent`. Tap a mood face → saves a minimal
      entry (mood level + timestamp). "Add more" deep-links into the
      full entry form.
- [ ] Lock Screen widget: single mood-face row.
- [ ] Home Screen widget: mood face + last entry summary.

### 4.2 Siri / Shortcuts integration
- [ ] `AppShortcutsProvider` with "Log my mood" shortcut.
- [ ] Siri dialog: "How are you feeling?" → mood level → save.

### 4.3 Apple Watch quick-log (stretch)
- [-] WatchKit app with a simple mood picker + save. Syncs via
      `WatchConnectivity` or shared SwiftData container.
- [-] Needs product decision: scope and priority.

---

## P5 — Explainability & Education

### 5.1 "Why this number?" tap-through
- [ ] Each numeric insight card (posterior risk, change-point
      probability, forecast CI, etc.) gets a tap-through sheet that
      explains in plain language what the number means, what data drove
      it, and what would make it change.
- [ ] Template: "This number represents [concept]. It's currently
      [value] because [top 2 evidence signals]. It would [go up/down]
      if [actionable factor]."

### 5.2 Psychoeducation library
- [-] Short, curated articles: "What is bipolar disorder?", "What are
      prodromal symptoms?", "How does sleep affect mood stability?",
      "What is a safety plan and why does it matter?"
- [-] Needs product decision: author in-house or link to NIMH/DBSA?

### 5.3 Model health transparency
- [ ] `ModelHealthService` already computes calibration metrics. Surface
      a "Data Quality" card on Insights showing: entries logged, data
      coverage, forecast accuracy trend, calibration error. Helps the
      user understand that more/better logging → better predictions.

---

## P6 — Weather Insights

### 6.1 Decide placement
- [-] **Option A (recommended):** Remove weather card from Insights tab.
      Surface weather correlation exclusively in the clinician PDF
      (page 2). Insights becomes more focused on clinically actionable
      signals.
- [-] **Option B:** Demote to a one-liner on an existing card (e.g.
      outlook card): "Rain slightly lowers your mood over 14 days."
- [-] **Option C:** Keep dedicated card but suppress when
      `weatherCoverageDays < 7` and show a "gathering data" hint when
      deltas are nil.
- [-] Needs product decision: pick A, B, or C.

### 6.2 Seasonal pattern detection
- [ ] Bipolar has strong seasonal components (spring/fall episode
      clustering). With 6+ months of data, detect seasonal mood
      patterns and surface "historically your mood dips in [month]."
- [ ] Source: simple month-binned mean comparison against the user's
      overall baseline. No new math service needed.

---

## Resolved / Shipped

Items that have already landed.

- [x] Weather data loss on entry edit (PR #1).
- [x] Stale Open-Meteo code set in rain/clear filter (PR #1).
- [x] Sleet/hail WMO code mismapping (PR #1).
- [x] Reverse geocoder failure canceling weather fetch (PR #1).
- [x] "Unknown" city persisted on geocoder miss (PR #1).
- [x] CI: Tuist installer broken (PR #1).
- [x] CI: coverage floor script always reporting 0% (PR #1).
