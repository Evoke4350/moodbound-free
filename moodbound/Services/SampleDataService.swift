import Foundation
import SwiftData

enum SampleDataService {
    enum DemoProfile: String, CaseIterable, Identifiable {
        case newlyDiagnosed
        case experiencedTracking
        case trackingNotDiagnosed
        case gatheringForProvider
        case depressiveEpisode
        case rapidCycling
        case mixedCrisis

        var id: String { rawValue }

        var title: String {
            switch self {
            case .newlyDiagnosed: return "Newly Diagnosed"
            case .experiencedTracking: return "Experienced With Bipolar Tracking"
            case .trackingNotDiagnosed: return "New To Tracking (Undiagnosed)"
            case .gatheringForProvider: return "Gathering Data For Provider"
            case .depressiveEpisode: return "Depressive Episode"
            case .rapidCycling: return "Rapid Cycling"
            case .mixedCrisis: return "Mixed State / Crisis"
            }
        }

        var subtitle: String {
            switch self {
            case .newlyDiagnosed:
                return "Early treatment period with noticeable adjustment and improved stability."
            case .experiencedTracking:
                return "Long-term tracker with tighter routines and lower volatility."
            case .trackingNotDiagnosed:
                return "Pattern discovery mode with mood/sleep variability and no medication logs."
            case .gatheringForProvider:
                return "Structured pre-appointment timeline with clear shifts and trigger evidence."
            case .depressiveEpisode:
                return "Extended low period with oversleeping, low energy, and partial medication adherence."
            case .rapidCycling:
                return "Fast-switching mood states over days. High volatility, sleep disruption, trigger-heavy."
            case .mixedCrisis:
                return "Mixed features with high energy + low mood. Safety signals active. Elevated concern."
            }
        }

        var recommendedDays: Int {
            switch self {
            case .newlyDiagnosed: return 120
            case .experiencedTracking: return 180
            case .trackingNotDiagnosed: return 90
            case .gatheringForProvider: return 120
            case .depressiveEpisode: return 90
            case .rapidCycling: return 60
            case .mixedCrisis: return 45
            }
        }
    }

    static func buildEntries(
        days: Int,
        endingAt now: Date = .now,
        calendar: Calendar = .current,
        profile: DemoProfile = .experiencedTracking
    ) -> [MoodEntry] {
        let clampedDays = max(1, days)
        let anchor = calendar.startOfDay(for: now)
        var entries: [MoodEntry] = []
        entries.reserveCapacity(clampedDays)

        for offset in 0..<clampedDays {
            let dayIndex = clampedDays - 1 - offset
            let date = calendar.date(byAdding: .day, value: -offset, to: anchor) ?? anchor

            let phase = phaseProfile(for: dayIndex, cycle: clampedDays, profile: profile)
            let waveA = sin(Double(dayIndex) * 2.0 * .pi / phase.moodPeriodA + phase.waveShift)
            let waveB = sin(Double(dayIndex) * 2.0 * .pi / phase.moodPeriodB)
            let noise = phase.noiseAmplitude * cos(Double(dayIndex) * 2.0 * .pi / phase.noisePeriod)
            let rawMood = phase.moodBaseline + (phase.waveAmplitudeA * waveA) + (phase.waveAmplitudeB * waveB) + noise
            let moodLevel = Int(max(-3.0, min(3.0, rawMood.rounded())))

            let rawEnergy = phase.energyBaseline + (rawMood * phase.energyMoodCoupling) + (0.2 * cos(Double(dayIndex) * 2.0 * .pi / 9.0))
            let energy = Int(max(1.0, min(5.0, rawEnergy.rounded())))

            let depressionOversleepBias = moodLevel <= -2 ? 0.8 : 0
            let sleepBase = phase.sleepBaseline - (Double(moodLevel) * phase.sleepMoodCoupling) + depressionOversleepBias
            let sleepNoise = phase.sleepNoiseAmplitude * cos(Double(dayIndex) * 2.0 * .pi / phase.sleepNoisePeriod)
            let sleepHours = max(4.0, min(10.8, sleepBase + sleepNoise))

            let irritability = Int(max(0.0, min(3.0, (abs(Double(moodLevel)) * 0.55 + 0.6).rounded())))
            let anxiety = Int(max(0.0, min(3.0, (abs(Double(moodLevel)) * 0.6 + 0.4).rounded())))

            let hourShift = 9.0 + (0.9 * sin(Double(dayIndex) * 2.0 * .pi / 8.0))
            let timestamp = date.addingTimeInterval(hourShift * 3600.0)

            let note = noteTemplate(for: moodLevel, phase: phase.phaseName, dayIndex: dayIndex, profile: profile)

            let entry = MoodEntry(
                timestamp: timestamp,
                moodLevel: moodLevel,
                energy: energy,
                sleepHours: sleepHours,
                irritability: irritability,
                anxiety: anxiety,
                note: note
            )
            entries.append(entry)
        }

        return entries
    }

    static func insertMissingDailyEntries(
        days: Int,
        endingAt now: Date = .now,
        context: ModelContext,
        calendar: Calendar = .current,
        profile: DemoProfile = .experiencedTracking
    ) throws -> Int {
        let candidates = buildEntries(days: days, endingAt: now, calendar: calendar, profile: profile)
        let cutoff = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: calendar.startOfDay(for: now)) ?? now

        var descriptor = FetchDescriptor<MoodEntry>(
            predicate: #Predicate { $0.timestamp >= cutoff }
        )
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .forward)]
        let existing = try context.fetch(descriptor)
        let existingDays = Set(existing.map { calendar.startOfDay(for: $0.timestamp) })
        let lookups = try supportingEntityLookup(context: context)

        var inserted = 0
        for entry in candidates {
            let day = calendar.startOfDay(for: entry.timestamp)
            guard !existingDays.contains(day) else { continue }
            attachSupportingEvents(to: entry, lookups: lookups, dayIndex: inserted, profile: profile)
            context.insert(entry)
            inserted += 1
        }

        if inserted > 0 {
            try context.save()
        }
        return inserted
    }

    static func replaceAllWithAppStoreDataset(
        days: Int = 120,
        endingAt now: Date = .now,
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> Int {
        try replaceAllEntries(context: context)
        return try insertMissingDailyEntries(days: days, endingAt: now, context: context, calendar: calendar, profile: .experiencedTracking)
    }

    static func replaceAllWithDemoProfile(
        profile: DemoProfile,
        days: Int? = nil,
        endingAt now: Date = .now,
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> Int {
        try replaceAllEntries(context: context)
        return try insertMissingDailyEntries(
            days: days ?? profile.recommendedDays,
            endingAt: now,
            context: context,
            calendar: calendar,
            profile: profile
        )
    }

    private static func replaceAllEntries(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<MoodEntry>())
        for entry in existing {
            context.delete(entry)
        }
        try context.save()
    }

    private struct PhaseProfile {
        let phaseName: String
        let moodBaseline: Double
        let sleepBaseline: Double
        let energyBaseline: Double
        let waveAmplitudeA: Double
        let waveAmplitudeB: Double
        let waveShift: Double
        let moodPeriodA: Double
        let moodPeriodB: Double
        let noiseAmplitude: Double
        let noisePeriod: Double
        let sleepNoiseAmplitude: Double
        let sleepNoisePeriod: Double
        let sleepMoodCoupling: Double
        let energyMoodCoupling: Double
    }

    private static func phaseProfile(for dayIndex: Int, cycle: Int, profile: DemoProfile) -> PhaseProfile {
        let normalized = Double(dayIndex) / Double(max(1, cycle - 1))
        switch profile {
        case .newlyDiagnosed:
            switch normalized {
            case ..<0.22:
                return PhaseProfile(phaseName: "pre-diagnosis low", moodBaseline: -1.6, sleepBaseline: 9.2, energyBaseline: 2.0, waveAmplitudeA: 0.9, waveAmplitudeB: 0.45, waveShift: 0, moodPeriodA: 14, moodPeriodB: 36, noiseAmplitude: 0.18, noisePeriod: 6, sleepNoiseAmplitude: 0.5, sleepNoisePeriod: 7, sleepMoodCoupling: 0.5, energyMoodCoupling: 0.6)
            case ..<0.45:
                return PhaseProfile(phaseName: "early treatment", moodBaseline: -0.8, sleepBaseline: 8.2, energyBaseline: 2.5, waveAmplitudeA: 0.75, waveAmplitudeB: 0.4, waveShift: 0.4, moodPeriodA: 15, moodPeriodB: 39, noiseAmplitude: 0.2, noisePeriod: 7, sleepNoiseAmplitude: 0.45, sleepNoisePeriod: 8, sleepMoodCoupling: 0.48, energyMoodCoupling: 0.58)
            case ..<0.7:
                return PhaseProfile(phaseName: "adjustment", moodBaseline: -0.2, sleepBaseline: 7.6, energyBaseline: 2.9, waveAmplitudeA: 0.65, waveAmplitudeB: 0.35, waveShift: 0.7, moodPeriodA: 17, moodPeriodB: 42, noiseAmplitude: 0.16, noisePeriod: 8, sleepNoiseAmplitude: 0.42, sleepNoisePeriod: 8, sleepMoodCoupling: 0.44, energyMoodCoupling: 0.54)
            case ..<0.86:
                return PhaseProfile(phaseName: "hypomanic blip", moodBaseline: 1.2, sleepBaseline: 6.4, energyBaseline: 3.9, waveAmplitudeA: 0.85, waveAmplitudeB: 0.3, waveShift: 1.1, moodPeriodA: 13, moodPeriodB: 34, noiseAmplitude: 0.22, noisePeriod: 6, sleepNoiseAmplitude: 0.52, sleepNoisePeriod: 7, sleepMoodCoupling: 0.55, energyMoodCoupling: 0.63)
            default:
                return PhaseProfile(phaseName: "stabilizing", moodBaseline: 0.1, sleepBaseline: 7.2, energyBaseline: 3.2, waveAmplitudeA: 0.45, waveAmplitudeB: 0.25, waveShift: 0.8, moodPeriodA: 20, moodPeriodB: 45, noiseAmplitude: 0.14, noisePeriod: 9, sleepNoiseAmplitude: 0.36, sleepNoisePeriod: 9, sleepMoodCoupling: 0.42, energyMoodCoupling: 0.5)
            }
        case .experiencedTracking:
            switch normalized {
            case ..<0.35:
                return PhaseProfile(phaseName: "stable baseline", moodBaseline: -0.1, sleepBaseline: 7.4, energyBaseline: 3.2, waveAmplitudeA: 0.45, waveAmplitudeB: 0.25, waveShift: 0.1, moodPeriodA: 18, moodPeriodB: 44, noiseAmplitude: 0.12, noisePeriod: 8, sleepNoiseAmplitude: 0.3, sleepNoisePeriod: 9, sleepMoodCoupling: 0.38, energyMoodCoupling: 0.46)
            case ..<0.58:
                return PhaseProfile(phaseName: "mild dip", moodBaseline: -0.8, sleepBaseline: 8.2, energyBaseline: 2.5, waveAmplitudeA: 0.55, waveAmplitudeB: 0.3, waveShift: 0.2, moodPeriodA: 17, moodPeriodB: 40, noiseAmplitude: 0.14, noisePeriod: 8, sleepNoiseAmplitude: 0.35, sleepNoisePeriod: 8, sleepMoodCoupling: 0.4, energyMoodCoupling: 0.5)
            case ..<0.78:
                return PhaseProfile(phaseName: "recovery", moodBaseline: -0.2, sleepBaseline: 7.6, energyBaseline: 2.9, waveAmplitudeA: 0.5, waveAmplitudeB: 0.28, waveShift: 0.4, moodPeriodA: 18, moodPeriodB: 42, noiseAmplitude: 0.13, noisePeriod: 9, sleepNoiseAmplitude: 0.34, sleepNoisePeriod: 9, sleepMoodCoupling: 0.38, energyMoodCoupling: 0.48)
            default:
                return PhaseProfile(phaseName: "slight elevation", moodBaseline: 0.7, sleepBaseline: 6.9, energyBaseline: 3.6, waveAmplitudeA: 0.6, waveAmplitudeB: 0.25, waveShift: 0.5, moodPeriodA: 16, moodPeriodB: 39, noiseAmplitude: 0.14, noisePeriod: 7, sleepNoiseAmplitude: 0.36, sleepNoisePeriod: 8, sleepMoodCoupling: 0.44, energyMoodCoupling: 0.54)
            }
        case .trackingNotDiagnosed:
            switch normalized {
            case ..<0.3:
                return PhaseProfile(phaseName: "unknown baseline", moodBaseline: -0.5, sleepBaseline: 7.9, energyBaseline: 2.8, waveAmplitudeA: 0.75, waveAmplitudeB: 0.4, waveShift: 0.6, moodPeriodA: 16, moodPeriodB: 37, noiseAmplitude: 0.24, noisePeriod: 6, sleepNoiseAmplitude: 0.55, sleepNoisePeriod: 7, sleepMoodCoupling: 0.5, energyMoodCoupling: 0.58)
            case ..<0.56:
                return PhaseProfile(phaseName: "activation swings", moodBaseline: 0.9, sleepBaseline: 6.7, energyBaseline: 3.8, waveAmplitudeA: 1.0, waveAmplitudeB: 0.45, waveShift: 1.0, moodPeriodA: 14, moodPeriodB: 31, noiseAmplitude: 0.28, noisePeriod: 5, sleepNoiseAmplitude: 0.58, sleepNoisePeriod: 6, sleepMoodCoupling: 0.58, energyMoodCoupling: 0.64)
            case ..<0.8:
                return PhaseProfile(phaseName: "depressive stretch", moodBaseline: -1.4, sleepBaseline: 9.0, energyBaseline: 2.1, waveAmplitudeA: 0.9, waveAmplitudeB: 0.35, waveShift: 1.3, moodPeriodA: 15, moodPeriodB: 34, noiseAmplitude: 0.26, noisePeriod: 6, sleepNoiseAmplitude: 0.6, sleepNoisePeriod: 7, sleepMoodCoupling: 0.54, energyMoodCoupling: 0.62)
            default:
                return PhaseProfile(phaseName: "partial rebound", moodBaseline: -0.1, sleepBaseline: 7.6, energyBaseline: 2.9, waveAmplitudeA: 0.7, waveAmplitudeB: 0.3, waveShift: 0.8, moodPeriodA: 17, moodPeriodB: 40, noiseAmplitude: 0.22, noisePeriod: 7, sleepNoiseAmplitude: 0.45, sleepNoisePeriod: 8, sleepMoodCoupling: 0.48, energyMoodCoupling: 0.56)
            }
        case .gatheringForProvider:
            switch normalized {
            case ..<0.25:
                return PhaseProfile(phaseName: "euthymic baseline", moodBaseline: 0.0, sleepBaseline: 7.4, energyBaseline: 3.1, waveAmplitudeA: 0.4, waveAmplitudeB: 0.2, waveShift: 0.2, moodPeriodA: 19, moodPeriodB: 44, noiseAmplitude: 0.1, noisePeriod: 9, sleepNoiseAmplitude: 0.28, sleepNoisePeriod: 9, sleepMoodCoupling: 0.36, energyMoodCoupling: 0.44)
            case ..<0.48:
                return PhaseProfile(phaseName: "mixed-feature period", moodBaseline: 0.2, sleepBaseline: 6.9, energyBaseline: 3.4, waveAmplitudeA: 1.05, waveAmplitudeB: 0.5, waveShift: 1.4, moodPeriodA: 10, moodPeriodB: 23, noiseAmplitude: 0.3, noisePeriod: 4, sleepNoiseAmplitude: 0.62, sleepNoisePeriod: 5, sleepMoodCoupling: 0.62, energyMoodCoupling: 0.66)
            case ..<0.72:
                return PhaseProfile(phaseName: "major depression", moodBaseline: -1.9, sleepBaseline: 9.4, energyBaseline: 1.9, waveAmplitudeA: 0.85, waveAmplitudeB: 0.3, waveShift: 0.5, moodPeriodA: 18, moodPeriodB: 39, noiseAmplitude: 0.18, noisePeriod: 7, sleepNoiseAmplitude: 0.5, sleepNoisePeriod: 8, sleepMoodCoupling: 0.5, energyMoodCoupling: 0.58)
            default:
                return PhaseProfile(phaseName: "re-engagement", moodBaseline: -0.3, sleepBaseline: 7.8, energyBaseline: 2.8, waveAmplitudeA: 0.55, waveAmplitudeB: 0.28, waveShift: 0.7, moodPeriodA: 17, moodPeriodB: 41, noiseAmplitude: 0.15, noisePeriod: 8, sleepNoiseAmplitude: 0.36, sleepNoisePeriod: 8, sleepMoodCoupling: 0.42, energyMoodCoupling: 0.5)
            }

        case .depressiveEpisode:
            switch normalized {
            case ..<0.15:
                return PhaseProfile(phaseName: "pre-episode baseline", moodBaseline: -0.3, sleepBaseline: 7.5, energyBaseline: 3.0, waveAmplitudeA: 0.4, waveAmplitudeB: 0.2, waveShift: 0, moodPeriodA: 18, moodPeriodB: 42, noiseAmplitude: 0.12, noisePeriod: 8, sleepNoiseAmplitude: 0.3, sleepNoisePeriod: 9, sleepMoodCoupling: 0.4, energyMoodCoupling: 0.5)
            case ..<0.35:
                return PhaseProfile(phaseName: "sliding down", moodBaseline: -1.2, sleepBaseline: 8.6, energyBaseline: 2.3, waveAmplitudeA: 0.5, waveAmplitudeB: 0.25, waveShift: 0.3, moodPeriodA: 16, moodPeriodB: 38, noiseAmplitude: 0.15, noisePeriod: 7, sleepNoiseAmplitude: 0.4, sleepNoisePeriod: 8, sleepMoodCoupling: 0.5, energyMoodCoupling: 0.55)
            case ..<0.65:
                return PhaseProfile(phaseName: "deep depression", moodBaseline: -2.3, sleepBaseline: 9.8, energyBaseline: 1.6, waveAmplitudeA: 0.6, waveAmplitudeB: 0.2, waveShift: 0.5, moodPeriodA: 20, moodPeriodB: 45, noiseAmplitude: 0.1, noisePeriod: 9, sleepNoiseAmplitude: 0.55, sleepNoisePeriod: 7, sleepMoodCoupling: 0.55, energyMoodCoupling: 0.6)
            case ..<0.82:
                return PhaseProfile(phaseName: "flattened", moodBaseline: -1.8, sleepBaseline: 9.2, energyBaseline: 1.8, waveAmplitudeA: 0.3, waveAmplitudeB: 0.15, waveShift: 0.6, moodPeriodA: 22, moodPeriodB: 48, noiseAmplitude: 0.08, noisePeriod: 10, sleepNoiseAmplitude: 0.45, sleepNoisePeriod: 8, sleepMoodCoupling: 0.5, energyMoodCoupling: 0.55)
            default:
                return PhaseProfile(phaseName: "early recovery", moodBaseline: -0.9, sleepBaseline: 8.4, energyBaseline: 2.2, waveAmplitudeA: 0.45, waveAmplitudeB: 0.2, waveShift: 0.4, moodPeriodA: 18, moodPeriodB: 40, noiseAmplitude: 0.14, noisePeriod: 8, sleepNoiseAmplitude: 0.38, sleepNoisePeriod: 8, sleepMoodCoupling: 0.45, energyMoodCoupling: 0.52)
            }

        case .rapidCycling:
            switch normalized {
            case ..<0.2:
                return PhaseProfile(phaseName: "hypomanic burst", moodBaseline: 1.8, sleepBaseline: 5.4, energyBaseline: 4.4, waveAmplitudeA: 1.2, waveAmplitudeB: 0.6, waveShift: 0, moodPeriodA: 7, moodPeriodB: 15, noiseAmplitude: 0.35, noisePeriod: 3, sleepNoiseAmplitude: 0.7, sleepNoisePeriod: 4, sleepMoodCoupling: 0.65, energyMoodCoupling: 0.7)
            case ..<0.4:
                return PhaseProfile(phaseName: "crash", moodBaseline: -2.0, sleepBaseline: 10.0, energyBaseline: 1.7, waveAmplitudeA: 0.8, waveAmplitudeB: 0.4, waveShift: 1.5, moodPeriodA: 8, moodPeriodB: 18, noiseAmplitude: 0.3, noisePeriod: 4, sleepNoiseAmplitude: 0.65, sleepNoisePeriod: 5, sleepMoodCoupling: 0.6, energyMoodCoupling: 0.65)
            case ..<0.6:
                return PhaseProfile(phaseName: "second surge", moodBaseline: 1.5, sleepBaseline: 5.8, energyBaseline: 4.1, waveAmplitudeA: 1.1, waveAmplitudeB: 0.55, waveShift: 2.0, moodPeriodA: 6, moodPeriodB: 14, noiseAmplitude: 0.38, noisePeriod: 3, sleepNoiseAmplitude: 0.72, sleepNoisePeriod: 4, sleepMoodCoupling: 0.62, energyMoodCoupling: 0.68)
            case ..<0.8:
                return PhaseProfile(phaseName: "second crash", moodBaseline: -1.6, sleepBaseline: 9.4, energyBaseline: 2.0, waveAmplitudeA: 0.9, waveAmplitudeB: 0.45, waveShift: 2.8, moodPeriodA: 9, moodPeriodB: 19, noiseAmplitude: 0.32, noisePeriod: 4, sleepNoiseAmplitude: 0.6, sleepNoisePeriod: 5, sleepMoodCoupling: 0.58, energyMoodCoupling: 0.63)
            default:
                return PhaseProfile(phaseName: "unstable plateau", moodBaseline: 0.3, sleepBaseline: 7.0, energyBaseline: 3.2, waveAmplitudeA: 1.0, waveAmplitudeB: 0.5, waveShift: 3.0, moodPeriodA: 8, moodPeriodB: 16, noiseAmplitude: 0.34, noisePeriod: 4, sleepNoiseAmplitude: 0.65, sleepNoisePeriod: 5, sleepMoodCoupling: 0.55, energyMoodCoupling: 0.6)
            }

        case .mixedCrisis:
            switch normalized {
            case ..<0.2:
                return PhaseProfile(phaseName: "pre-crisis normal", moodBaseline: 0.1, sleepBaseline: 7.3, energyBaseline: 3.1, waveAmplitudeA: 0.4, waveAmplitudeB: 0.2, waveShift: 0, moodPeriodA: 18, moodPeriodB: 42, noiseAmplitude: 0.12, noisePeriod: 8, sleepNoiseAmplitude: 0.3, sleepNoisePeriod: 9, sleepMoodCoupling: 0.4, energyMoodCoupling: 0.48)
            case ..<0.45:
                return PhaseProfile(phaseName: "mixed escalation", moodBaseline: -0.8, sleepBaseline: 5.2, energyBaseline: 4.2, waveAmplitudeA: 1.3, waveAmplitudeB: 0.65, waveShift: 1.0, moodPeriodA: 6, moodPeriodB: 13, noiseAmplitude: 0.4, noisePeriod: 3, sleepNoiseAmplitude: 0.75, sleepNoisePeriod: 4, sleepMoodCoupling: 0.7, energyMoodCoupling: 0.72)
            case ..<0.7:
                return PhaseProfile(phaseName: "full mixed state", moodBaseline: -1.4, sleepBaseline: 4.8, energyBaseline: 4.5, waveAmplitudeA: 1.5, waveAmplitudeB: 0.7, waveShift: 1.8, moodPeriodA: 5, moodPeriodB: 11, noiseAmplitude: 0.45, noisePeriod: 3, sleepNoiseAmplitude: 0.8, sleepNoisePeriod: 3, sleepMoodCoupling: 0.75, energyMoodCoupling: 0.75)
            case ..<0.85:
                return PhaseProfile(phaseName: "crisis peak", moodBaseline: -2.0, sleepBaseline: 4.5, energyBaseline: 4.0, waveAmplitudeA: 1.2, waveAmplitudeB: 0.6, waveShift: 2.2, moodPeriodA: 6, moodPeriodB: 12, noiseAmplitude: 0.42, noisePeriod: 3, sleepNoiseAmplitude: 0.78, sleepNoisePeriod: 4, sleepMoodCoupling: 0.72, energyMoodCoupling: 0.7)
            default:
                return PhaseProfile(phaseName: "post-crisis stabilizing", moodBaseline: -0.6, sleepBaseline: 6.8, energyBaseline: 3.0, waveAmplitudeA: 0.7, waveAmplitudeB: 0.35, waveShift: 1.5, moodPeriodA: 12, moodPeriodB: 28, noiseAmplitude: 0.25, noisePeriod: 5, sleepNoiseAmplitude: 0.5, sleepNoisePeriod: 6, sleepMoodCoupling: 0.55, energyMoodCoupling: 0.58)
            }
        }
    }

    private static func noteTemplate(for moodLevel: Int, phase: String, dayIndex: Int, profile: DemoProfile) -> String {
        let prefix: String
        switch moodLevel {
        case ...(-2): prefix = "Felt heavy and slower than usual."
        case -1: prefix = "Some drag, but still functional."
        case 0: prefix = "Mostly balanced day."
        case 1: prefix = "Noticed extra momentum."
        default: prefix = "Very energized with fast pace."
        }

        let phaseDetail: String
        switch phase {
        case "low": phaseDetail = "Focused on basic routines and lower-pressure tasks."
        case "activation": phaseDetail = "Needed extra grounding breaks to slow down."
        case "recovery": phaseDetail = "Sleep and routine consistency helped."
        case "mixed-feature period": phaseDetail = "Noticed overlapping high activation and low mood signals."
        case "major depression": phaseDetail = "Harder to initiate tasks and social contact."
        case "euthymic baseline": phaseDetail = "Daily rhythm was steady and predictable."
        case "deep depression": phaseDetail = "Could barely get out of bed. Everything felt pointless."
        case "flattened": phaseDetail = "Numb. Not sad exactly, just nothing."
        case "sliding down": phaseDetail = "Noticed things getting harder. Taking more effort to do simple things."
        case "early recovery": phaseDetail = "First day in a while where something felt okay."
        case "hypomanic burst": phaseDetail = "Ideas racing, started three projects. Felt amazing but couldn't focus."
        case "crash": phaseDetail = "Hit a wall. Yesterday's energy completely gone."
        case "second surge": phaseDetail = "Back up again. Spent too much money today."
        case "second crash": phaseDetail = "Down again. This back and forth is exhausting."
        case "unstable plateau": phaseDetail = "Not sure which direction things are going."
        case "mixed escalation": phaseDetail = "Agitated and restless but also hopeless. Worst combination."
        case "full mixed state": phaseDetail = "Can't sleep, can't relax, can't think straight. Mind won't stop."
        case "crisis peak": phaseDetail = "Called my therapist. This is too much."
        case "post-crisis stabilizing": phaseDetail = "Meds adjusted. Starting to feel less wired."
        default: phaseDetail = "Routine felt manageable."
        }

        let profileLine: String
        switch profile {
        case .newlyDiagnosed:
            profileLine = "Still learning patterns after diagnosis."
        case .experiencedTracking:
            profileLine = "Used established coping plan and regular check-ins."
        case .trackingNotDiagnosed:
            profileLine = "Tracking to understand patterns before seeking diagnosis."
        case .gatheringForProvider:
            profileLine = "Documented this clearly for next provider visit."
        case .depressiveEpisode:
            profileLine = "Everything feels heavier. Hard to get started on things."
        case .rapidCycling:
            profileLine = "Mood shifted again. Hard to keep up with the swings."
        case .mixedCrisis:
            profileLine = "Wired but miserable. Can't sleep but no motivation."
        }

        let suffix = dayIndex % 3 == 0 ? "Tracked sleep and triggers carefully." : "No immediate safety concerns."
        return "\(prefix) \(phaseDetail) \(profileLine) \(suffix)"
    }

    private struct SupportingLookup {
        let lamotrigine: Medication
        let quetiapine: Medication
        let stress: TriggerFactor
        let conflict: TriggerFactor
        let sleepLoss: TriggerFactor
        let caffeine: TriggerFactor
    }

    private static func supportingEntityLookup(context: ModelContext) throws -> SupportingLookup {
        let existingMeds = try context.fetch(FetchDescriptor<Medication>())
        let existingTriggers = try context.fetch(FetchDescriptor<TriggerFactor>())

        func medication(named name: String, dosage: String, schedule: String) -> Medication {
            if let found = existingMeds.first(where: { $0.normalizedName == Medication.normalize(name) }) {
                return found
            }
            let med = Medication(name: name, dosage: dosage, scheduleNote: schedule)
            context.insert(med)
            return med
        }

        func trigger(named name: String, category: String) -> TriggerFactor {
            if let found = existingTriggers.first(where: { $0.normalizedName == TriggerFactor.normalize(name) }) {
                return found
            }
            let factor = TriggerFactor(name: name, category: category)
            context.insert(factor)
            return factor
        }

        return SupportingLookup(
            lamotrigine: medication(named: "Lamotrigine", dosage: "200mg", schedule: "night"),
            quetiapine: medication(named: "Quetiapine", dosage: "50mg", schedule: "as needed"),
            stress: trigger(named: "Work Stress", category: "work"),
            conflict: trigger(named: "Conflict", category: "social"),
            sleepLoss: trigger(named: "Sleep Loss", category: "sleep"),
            caffeine: trigger(named: "Caffeine", category: "lifestyle")
        )
    }

    private static func attachSupportingEvents(to entry: MoodEntry, lookups: SupportingLookup, dayIndex: Int, profile: DemoProfile) {
        let activationBias = max(0, entry.moodLevel)
        let depressiveBias = max(0, -entry.moodLevel)

        switch profile {
        case .trackingNotDiagnosed:
            entry.medicationAdherenceEvents = []
        case .newlyDiagnosed:
            let lamotrigineTaken = ((dayIndex * 7 + 3) % 10) != 0
            entry.medicationAdherenceEvents = [
                MedicationAdherenceEvent(
                    timestamp: entry.timestamp,
                    taken: lamotrigineTaken,
                    medication: lookups.lamotrigine,
                    moodEntry: entry
                ),
            ]
        case .experiencedTracking:
            let lamotrigineTaken = ((dayIndex * 7 + 3) % 20) != 0
            let quetiapineTaken = entry.sleepHours < 6.0 || entry.moodLevel >= 2 ? ((dayIndex * 11 + 5) % 4 != 0) : ((dayIndex + 2) % 10 == 0)
            entry.medicationAdherenceEvents = [
                MedicationAdherenceEvent(
                    timestamp: entry.timestamp,
                    taken: lamotrigineTaken,
                    medication: lookups.lamotrigine,
                    moodEntry: entry
                ),
                MedicationAdherenceEvent(
                    timestamp: entry.timestamp,
                    taken: quetiapineTaken,
                    medication: lookups.quetiapine,
                    moodEntry: entry
                ),
            ]
        case .gatheringForProvider:
            let lamotrigineTaken = ((dayIndex * 5 + 2) % 12) != 0
            entry.medicationAdherenceEvents = [
                MedicationAdherenceEvent(
                    timestamp: entry.timestamp,
                    taken: lamotrigineTaken,
                    medication: lookups.lamotrigine,
                    moodEntry: entry
                ),
            ]
        case .depressiveEpisode:
            // Spotty adherence — hard to keep up when depressed
            let lamotrigineTaken = ((dayIndex * 3 + 1) % 5) != 0
            let quetiapineTaken = ((dayIndex * 7 + 2) % 4) != 0
            entry.medicationAdherenceEvents = [
                MedicationAdherenceEvent(
                    timestamp: entry.timestamp,
                    taken: lamotrigineTaken,
                    medication: lookups.lamotrigine,
                    moodEntry: entry
                ),
                MedicationAdherenceEvent(
                    timestamp: entry.timestamp,
                    taken: quetiapineTaken,
                    medication: lookups.quetiapine,
                    moodEntry: entry
                ),
            ]
        case .rapidCycling:
            // Takes meds but inconsistently during swings
            let lamotrigineTaken = ((dayIndex * 11 + 3) % 7) != 0
            entry.medicationAdherenceEvents = [
                MedicationAdherenceEvent(
                    timestamp: entry.timestamp,
                    taken: lamotrigineTaken,
                    medication: lookups.lamotrigine,
                    moodEntry: entry
                ),
            ]
        case .mixedCrisis:
            // Takes both but misses often during crisis
            let lamotrigineTaken = ((dayIndex * 5 + 1) % 6) != 0
            let quetiapineTaken = ((dayIndex * 3 + 2) % 3) != 0
            entry.medicationAdherenceEvents = [
                MedicationAdherenceEvent(
                    timestamp: entry.timestamp,
                    taken: lamotrigineTaken,
                    medication: lookups.lamotrigine,
                    moodEntry: entry
                ),
                MedicationAdherenceEvent(
                    timestamp: entry.timestamp,
                    taken: quetiapineTaken,
                    medication: lookups.quetiapine,
                    moodEntry: entry
                ),
            ]
        }

        var triggerEvents: [TriggerEvent] = []
        if ((dayIndex * 13 + 1) % 5 == 0) || entry.anxiety >= 2 || profile == .gatheringForProvider {
            triggerEvents.append(
                TriggerEvent(
                    timestamp: entry.timestamp,
                    intensity: min(3, 1 + entry.anxiety),
                    note: "Higher cognitive load.",
                    trigger: lookups.stress,
                    moodEntry: entry
                )
            )
        }
        if ((dayIndex * 17 + 2) % 11 == 0) || (entry.irritability >= 2 && activationBias > 0) {
            triggerEvents.append(
                TriggerEvent(
                    timestamp: entry.timestamp,
                    intensity: min(3, 1 + entry.irritability),
                    note: "Interpersonal friction.",
                    trigger: lookups.conflict,
                    moodEntry: entry
                )
            )
        }
        if entry.sleepHours < 6.2 || (depressiveBias > 1 && entry.sleepHours > 9.8) {
            triggerEvents.append(
                TriggerEvent(
                    timestamp: entry.timestamp,
                    intensity: entry.sleepHours < 5.2 ? 3 : 2,
                    note: "Sleep pattern disruption.",
                    trigger: lookups.sleepLoss,
                    moodEntry: entry
                )
            )
        }
        if activationBias >= 1 && ((dayIndex * 19 + 4) % 6 == 0) {
            triggerEvents.append(
                TriggerEvent(
                    timestamp: entry.timestamp,
                    intensity: min(3, 1 + activationBias),
                    note: "Extra caffeine intake.",
                    trigger: lookups.caffeine,
                    moodEntry: entry
                )
            )
        }

        entry.triggerEvents = triggerEvents
    }
}
