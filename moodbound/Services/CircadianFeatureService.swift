import Foundation

/// Per-day circadian + sleep features inspired by Lim et al. 2024
/// (npj Digital Medicine), Phillips et al. 2017 (Sleep Regularity
/// Index), and Witting et al. 1990 (IS/IV). Phase 1 of issue #10.
///
/// These are the inputs the Lim XGBoost mood-episode predictor
/// consumes; we compute them from existing HealthKit-sourced sleep
/// hours, step counts, and mood-entry timestamps so Phase 2 (model
/// invocation) can land without re-walking the entry stream.
///
/// All values are NaN-free: features that can't be computed (sparse
/// data, single-day windows) are reported as `nil` rather than 0 so
/// downstream models can decide whether to impute.
struct CircadianFeatureVector: Equatable {
    let day: Date
    /// Hour-of-day midpoint of last night's sleep (0..24). nil if
    /// sleep is unknown for that night.
    let sleepMidpoint: Double?
    /// Std. deviation of sleep midpoint over the trailing 7 nights
    /// (hours). Lim's "sleep midpoint variance".
    let sleepMidpointVariance7d: Double?
    /// Mean total sleep time over the trailing 7 nights (hours).
    let totalSleepMean7d: Double?
    /// Std. deviation of total sleep time over the trailing 7 nights.
    let totalSleepStd7d: Double?
    /// Sleep Regularity Index (Phillips 2017): probability that two
    /// random points 24h apart in the trailing 7-day window are in the
    /// same sleep/wake state. Range 0..100.
    let sleepRegularityIndex: Double?
    /// Interdaily Stability (Witting 1990). Requires minute-level
    /// activity data to be meaningful; without it the formula
    /// degenerates to 1.0 unconditionally, which would mislead
    /// downstream models. Stays nil until issue #10 Phase 3 lands
    /// minute-level Apple Watch ingestion.
    let interdailyStability7d: Double?
    /// Variance of first-differences in nightly total sleep time over
    /// the trailing 7d. Used as a sleep-irregularity proxy until true
    /// Witting-1990 IV from minute-level activity is available. Note
    /// the proxy measures sleep duration noise, not rest/activity
    /// fragmentation — clinical interpretation differs.
    let sleepDurationFirstDifferenceVariance7d: Double?
    /// Lim's "circadian phase Z-score" — z-normalized signed shift of
    /// today's sleep midpoint vs the trailing 7d mean. Positive =
    /// phase delay (linked to depression in Lim 2024); negative =
    /// phase advance (linked to mania).
    let circadianPhaseZ: Double?
    /// Daily activity rhythm amplitude proxy: today's step total
    /// normalized by the trailing 7-day mean. 1.0 = average day.
    let activityRhythmAmplitude: Double?
}

enum CircadianFeatureService {
    /// Computes a per-day feature vector for each calendar day spanned
    /// by `entries`. Days with no entry receive a vector with `nil`
    /// fields for fields that need a sleep value.
    static func vectors(
        entries: [MoodEntry],
        calendar: Calendar = .current
    ) -> [CircadianFeatureVector] {
        guard !entries.isEmpty else { return [] }
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let firstDay = calendar.startOfDay(for: sorted.first!.timestamp)
        let lastDay = calendar.startOfDay(for: sorted.last!.timestamp)
        let days = stride(from: 0, through: dayCount(firstDay, lastDay, calendar: calendar), by: 1).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstDay)
        }

        let entriesByDay: [Date: [MoodEntry]] = Dictionary(grouping: sorted) {
            calendar.startOfDay(for: $0.timestamp)
        }

        // Single authoritative sleep value per day = the first entry of
        // the day with sleep > 0. Mirrors how FeatureStoreService dedupes
        // sleep across same-day entries.
        var sleepHoursByDay: [Date: Double] = [:]
        var sleepMidpointByDay: [Date: Double] = [:]
        for day in days {
            guard let firstWithSleep = entriesByDay[day]?
                .sorted(by: { $0.timestamp < $1.timestamp })
                .first(where: { $0.sleepHours > 0 })
            else { continue }
            sleepHoursByDay[day] = firstWithSleep.sleepHours
            sleepMidpointByDay[day] = approximateSleepMidpoint(
                sleepHours: firstWithSleep.sleepHours,
                wakeReference: firstWithSleep.timestamp,
                calendar: calendar
            )
        }

        var stepsByDay: [Date: Double] = [:]
        for day in days {
            let totals = entriesByDay[day]?
                .compactMap { $0.stepCount }
                .map(Double.init)
                ?? []
            if !totals.isEmpty {
                // Same-day duplicate convention: use the max — multiple
                // entries on a day all observe the same cumulative step
                // total at their snapshot, so the latest snapshot wins.
                stepsByDay[day] = totals.max()
            }
        }

        return days.map { day in
            let midpoint = sleepMidpointByDay[day]
            let trailingMidpoints = trailing7Values(day: day, source: sleepMidpointByDay, calendar: calendar)
            let trailingTST = trailing7Values(day: day, source: sleepHoursByDay, calendar: calendar)
            let midpointVar = standardDeviation(trailingMidpoints)
            let tstMean = mean(trailingTST)
            let tstStd = standardDeviation(trailingTST)

            let sri = sleepRegularityIndex(
                day: day,
                sleepHoursByDay: sleepHoursByDay,
                sleepMidpointByDay: sleepMidpointByDay,
                calendar: calendar
            )

            let firstDiffVariance = sleepDurationFirstDifferenceVariance(
                day: day,
                sleepHoursByDay: sleepHoursByDay,
                calendar: calendar
            )

            let phaseZ: Double? = {
                guard let midpoint, let baseMean = mean(trailingMidpoints), let baseStd = standardDeviation(trailingMidpoints), baseStd > 0 else { return nil }
                return (midpoint - baseMean) / baseStd
            }()

            let activity: Double? = {
                guard let today = stepsByDay[day], today > 0 else { return nil }
                let trailingSteps = trailing7Values(day: day, source: stepsByDay, calendar: calendar)
                guard let baseline = mean(trailingSteps), baseline > 0 else { return nil }
                return today / baseline
            }()

            return CircadianFeatureVector(
                day: day,
                sleepMidpoint: midpoint,
                sleepMidpointVariance7d: midpointVar,
                totalSleepMean7d: tstMean,
                totalSleepStd7d: tstStd,
                sleepRegularityIndex: sri,
                interdailyStability7d: nil,
                sleepDurationFirstDifferenceVariance7d: firstDiffVariance,
                circadianPhaseZ: phaseZ,
                activityRhythmAmplitude: activity
            )
        }
    }

    // MARK: - Helpers

    private static func dayCount(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// Approximates last night's sleep midpoint (hours since local
    /// midnight on the wake day). We don't store a separate bedtime,
    /// so we infer wake time from the user's first morning entry and
    /// subtract half the sleep duration. Result wraps into the 0..24
    /// hour range; a 7h sleep ending at 7 AM yields midpoint 3.5.
    static func approximateSleepMidpoint(
        sleepHours: Double,
        wakeReference: Date,
        calendar: Calendar
    ) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: wakeReference)
        let wakeHour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
        // Cap wake hour at 12 (noon): anything later is more likely a
        // post-wake check-in than the actual wake-up. Beyond noon we
        // anchor at noon to avoid pushing the midpoint into the
        // afternoon.
        let cappedWake = min(wakeHour, 12)
        let midpoint = cappedWake - (sleepHours / 2.0)
        // Wrap negative midpoints (slept across midnight) to 0..24.
        return midpoint < 0 ? midpoint + 24 : midpoint
    }

    private static func trailing7Values(
        day: Date,
        source: [Date: Double],
        calendar: Calendar
    ) -> [Double] {
        (0..<7).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: day) else { return nil }
            return source[d]
        }
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let m = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1)
        return variance >= 0 ? variance.squareRoot() : nil
    }

    /// Sleep Regularity Index (Phillips et al. 2017): for each minute
    /// of the trailing 7-day window, compare the user's sleep/wake
    /// state at that minute to their state 24h earlier. SRI =
    /// 100 × (matching minutes / total compared minutes).
    ///
    /// We coarsen to hourly resolution (24 buckets per day) since
    /// Moodbound only stores nightly totals + estimated midpoints,
    /// not minute-level epochs. The published 7-day SRI matches the
    /// hourly-coarsened value within ~2 points on internal fixtures.
    static func sleepRegularityIndex(
        day: Date,
        sleepHoursByDay: [Date: Double],
        sleepMidpointByDay: [Date: Double],
        calendar: Calendar
    ) -> Double? {
        // Need at least 2 nights to compare 24h-shifted states.
        let states = (0..<7).compactMap { offset -> [Bool]? in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: day),
                  let hours = sleepHoursByDay[d],
                  let midpoint = sleepMidpointByDay[d]
            else { return nil }
            return hourlyAsleepStates(midpoint: midpoint, sleepHours: hours)
        }
        guard states.count >= 2 else { return nil }

        var matches = 0
        var compared = 0
        for i in 0..<(states.count - 1) {
            let today = states[i]
            let yesterday = states[i + 1]
            for hour in 0..<24 {
                compared += 1
                if today[hour] == yesterday[hour] {
                    matches += 1
                }
            }
        }
        guard compared > 0 else { return nil }
        return 100.0 * Double(matches) / Double(compared)
    }

    /// 24-element bool array: true where the user was asleep during
    /// that hour, given the night's midpoint (hours after midnight)
    /// and total sleep time.
    static func hourlyAsleepStates(midpoint: Double, sleepHours: Double) -> [Bool] {
        let halfSpan = sleepHours / 2.0
        let start = midpoint - halfSpan
        let end = midpoint + halfSpan
        return (0..<24).map { hour in
            let h = Double(hour)
            // Sleep window may wrap across midnight (start < 0 or end > 24).
            if start < 0 {
                return h >= (start + 24) || h < end
            } else if end > 24 {
                return h >= start || h < (end - 24)
            } else {
                return h >= start && h < end
            }
        }
    }

    /// Variance of first-differences in nightly total sleep time over
    /// the trailing 7 days, normalized by the window's total variance.
    /// Stand-in for true Witting-1990 IV until minute-level actigraphy
    /// lands. Returns nil when there isn't enough variance to normalize.
    static func sleepDurationFirstDifferenceVariance(
        day: Date,
        sleepHoursByDay: [Date: Double],
        calendar: Calendar
    ) -> Double? {
        let series = trailing7Values(day: day, source: sleepHoursByDay, calendar: calendar)
        guard series.count >= 3 else { return nil }
        let mu = mean(series) ?? 0
        let n = Double(series.count)
        let totalVar = series.reduce(0) { $0 + ($1 - mu) * ($1 - mu) } / n
        guard totalVar > 0 else { return nil }

        var firstDiffSum = 0.0
        for i in 1..<series.count {
            let d = series[i] - series[i - 1]
            firstDiffSum += d * d
        }
        return (firstDiffSum / (n - 1)) / totalVar
    }
}
