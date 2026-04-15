import Foundation
@testable import moodbound

enum RealisticMoodDatasetFactory {
    struct Scenario {
        let entries: [MoodEntry]
        let medications: [Medication]
        let triggers: [TriggerFactor]
    }

    static func makeScenario(
        days: Int,
        startDate: Date = dateUTC(2025, 1, 1, 0, 0)
    ) -> Scenario {
        let count = max(1, days)
        let primaryMed = Medication(name: "Lamotrigine", dosage: "200mg", scheduleNote: "night")
        let rescueMed = Medication(name: "Quetiapine", dosage: "50mg", scheduleNote: "as needed")

        let stress = TriggerFactor(name: "Stress", category: "work")
        let conflict = TriggerFactor(name: "Conflict", category: "social")
        let sleepLoss = TriggerFactor(name: "Sleep Loss", category: "sleep")

        var entries: [MoodEntry] = []
        entries.reserveCapacity(count)

        for day in 0..<count {
            let phase = phaseProfile(day: day)
            let weeklyWave = 0.35 * sin(Double(day) * (2.0 * .pi / 7.0))
            let moodContinuous = clamp(phase.moodBaseline + weeklyWave + deterministicNoise(day, scale: 0.25), min: -3.0, max: 3.0)
            let moodLevel = Int(clamp(Double(Int((moodContinuous).rounded())), min: -3.0, max: 3.0))

            let energyContinuous = clamp(3.0 + (moodContinuous * 0.65) + deterministicNoise(day + 11, scale: 0.45), min: 1.0, max: 5.0)
            let energy = Int((energyContinuous).rounded())

            let sleepHours = clamp(
                phase.sleepBaseline + (0.25 * cos(Double(day) * (2.0 * .pi / 9.0))) + deterministicNoise(day + 23, scale: 0.55),
                min: 3.5,
                max: 12.0
            )

            let anxiety = Int(clamp(phase.anxietyBaseline + (abs(moodContinuous) * 0.35) + deterministicNoise(day + 37, scale: 0.55), min: 0.0, max: 3.0).rounded())
            let irritability = Int(clamp(phase.irritabilityBaseline + max(0, moodContinuous) * 0.45 + deterministicNoise(day + 47, scale: 0.45), min: 0.0, max: 3.0).rounded())

            let circadianHour = clamp(phase.baseHour + phase.circadianDriftPerDay * Double(day % 28) + deterministicNoise(day + 7, scale: 0.35), min: 5.5, max: 23.0)
            let timestamp = startDate.addingTimeInterval(Double(day) * 86_400).addingTimeInterval(circadianHour * 3_600)

            let entry = MoodEntry(
                timestamp: timestamp,
                moodLevel: moodLevel,
                energy: energy,
                sleepHours: sleepHours,
                irritability: irritability,
                anxiety: anxiety,
                note: ""
            )

            let primaryTaken = adherenceDecision(day: day, baseAdherence: phase.primaryAdherence, variabilitySeed: 3)
            let rescueTaken = adherenceDecision(day: day, baseAdherence: phase.rescueAdherence, variabilitySeed: 17)

            let medEvents = [
                MedicationAdherenceEvent(timestamp: timestamp, taken: primaryTaken, medication: primaryMed, moodEntry: entry),
                MedicationAdherenceEvent(timestamp: timestamp, taken: rescueTaken, medication: rescueMed, moodEntry: entry),
            ]
            entry.medicationAdherenceEvents = medEvents

            var triggerEvents: [TriggerEvent] = []
            if anxiety >= 2 || stressPulse(day: day) > 0.72 {
                triggerEvents.append(TriggerEvent(timestamp: timestamp, intensity: max(1, anxiety), trigger: stress, moodEntry: entry))
            }
            if irritability >= 2 && ((day + 2) % 5 == 0) {
                triggerEvents.append(TriggerEvent(timestamp: timestamp, intensity: max(1, irritability), trigger: conflict, moodEntry: entry))
            }
            if sleepHours < 6.0 || (phase.isActivationEpisode && sleepHours < 6.5) {
                triggerEvents.append(TriggerEvent(timestamp: timestamp, intensity: sleepHours < 5.0 ? 3 : 2, trigger: sleepLoss, moodEntry: entry))
            }
            entry.triggerEvents = triggerEvents

            entries.append(entry)
        }

        return Scenario(
            entries: entries,
            medications: [primaryMed, rescueMed],
            triggers: [stress, conflict, sleepLoss]
        )
    }

    private struct PhaseProfile {
        let moodBaseline: Double
        let sleepBaseline: Double
        let anxietyBaseline: Double
        let irritabilityBaseline: Double
        let primaryAdherence: Double
        let rescueAdherence: Double
        let baseHour: Double
        let circadianDriftPerDay: Double
        let isActivationEpisode: Bool
    }

    // 168-day cycle with euthymic, depressive, recovery, activation, stabilization windows.
    private static func phaseProfile(day: Int) -> PhaseProfile {
        let cycleDay = day % 168
        switch cycleDay {
        case 0..<42:
            return PhaseProfile(
                moodBaseline: -0.2,
                sleepBaseline: 7.4,
                anxietyBaseline: 1.1,
                irritabilityBaseline: 0.8,
                primaryAdherence: 0.92,
                rescueAdherence: 0.74,
                baseHour: 8.8,
                circadianDriftPerDay: 0.01,
                isActivationEpisode: false
            )
        case 42..<84:
            return PhaseProfile(
                moodBaseline: -1.7,
                sleepBaseline: 9.1,
                anxietyBaseline: 1.9,
                irritabilityBaseline: 1.2,
                primaryAdherence: 0.82,
                rescueAdherence: 0.62,
                baseHour: 10.0,
                circadianDriftPerDay: -0.02,
                isActivationEpisode: false
            )
        case 84..<112:
            return PhaseProfile(
                moodBaseline: -0.5,
                sleepBaseline: 7.8,
                anxietyBaseline: 1.3,
                irritabilityBaseline: 1.0,
                primaryAdherence: 0.9,
                rescueAdherence: 0.7,
                baseHour: 8.9,
                circadianDriftPerDay: 0.01,
                isActivationEpisode: false
            )
        case 112..<147:
            return PhaseProfile(
                moodBaseline: 1.9,
                sleepBaseline: 5.7,
                anxietyBaseline: 2.1,
                irritabilityBaseline: 2.1,
                primaryAdherence: 0.73,
                rescueAdherence: 0.58,
                baseHour: 7.2,
                circadianDriftPerDay: 0.05,
                isActivationEpisode: true
            )
        default:
            return PhaseProfile(
                moodBaseline: 0.2,
                sleepBaseline: 7.1,
                anxietyBaseline: 1.0,
                irritabilityBaseline: 0.9,
                primaryAdherence: 0.9,
                rescueAdherence: 0.72,
                baseHour: 8.5,
                circadianDriftPerDay: 0.0,
                isActivationEpisode: false
            )
        }
    }

    private static func stressPulse(day: Int) -> Double {
        let raw = sin(Double((day * 17) % 97) * 0.27) + cos(Double((day * 11) % 89) * 0.19)
        return clamp((raw + 2.0) / 4.0, min: 0, max: 1)
    }

    private static func adherenceDecision(day: Int, baseAdherence: Double, variabilitySeed: Int) -> Bool {
        let pulse = stressPulse(day: day + variabilitySeed)
        return pulse <= baseAdherence
    }

    private static func deterministicNoise(_ seed: Int, scale: Double) -> Double {
        let a = sin(Double(seed) * 12.9898)
        let b = cos(Double(seed) * 78.233)
        let combined = (a + b) * 0.5 // approx in [-1, 1]
        return combined * scale
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private static func dateUTC(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
