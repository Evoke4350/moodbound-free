import Foundation

struct MedicationTrajectory: Equatable {
    let medicationName: String
    let shortWindowDelta: Double
    let mediumWindowDelta: Double
    let uncertainty: Double
    let sampleCount: Int
    let isDataSufficient: Bool
}

enum MedicationTrajectoryService {
    static func trajectories(entries: [MoodEntry], minimumSamples: Int = 4) -> [MedicationTrajectory] {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 6 else { return [] }

        let riskByEntryId = Dictionary(uniqueKeysWithValues: sorted.map { (ObjectIdentifier($0), riskScore($0)) })
        let indexByEntryId = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { (ObjectIdentifier($0.element), $0.offset) })

        var groupedTakenShort: [String: [Double]] = [:]
        var groupedMissedShort: [String: [Double]] = [:]
        var groupedTakenMedium: [String: [Double]] = [:]
        var groupedMissedMedium: [String: [Double]] = [:]

        for entry in sorted {
            let entryId = ObjectIdentifier(entry)
            guard let index = indexByEntryId[entryId], let baseRisk = riskByEntryId[entryId] else { continue }

            let futureShort = meanFutureRisk(from: index, count: 1, sorted: sorted, riskByEntryId: riskByEntryId)
            let futureMedium = meanFutureRisk(from: index, count: 7, sorted: sorted, riskByEntryId: riskByEntryId)
            guard let short = futureShort, let medium = futureMedium else { continue }

            for event in entry.medicationAdherenceEvents {
                guard let name = event.medication?.name, !name.isEmpty else { continue }
                let shortDelta = short - baseRisk
                let mediumDelta = medium - baseRisk
                if event.taken {
                    groupedTakenShort[name, default: []].append(shortDelta)
                    groupedTakenMedium[name, default: []].append(mediumDelta)
                } else {
                    groupedMissedShort[name, default: []].append(shortDelta)
                    groupedMissedMedium[name, default: []].append(mediumDelta)
                }
            }
        }

        let names = Set(groupedTakenShort.keys).union(groupedMissedShort.keys)
        return names.compactMap { name -> MedicationTrajectory? in
            let takenShort = groupedTakenShort[name] ?? []
            let missedShort = groupedMissedShort[name] ?? []
            let takenMedium = groupedTakenMedium[name] ?? []
            let missedMedium = groupedMissedMedium[name] ?? []

            let support = min(takenShort.count, missedShort.count)
            let sufficient = support >= minimumSamples
            // Both arms must have at least one observation before we can produce
            // a delta; otherwise average([])==0 would silently masquerade as a
            // real risk score and the difference would be meaningless. The
            // producer loop above appends to short and medium together, so the
            // medium arrays' counts mirror the short arrays' counts.
            guard let takenShortAvg = mean(takenShort),
                  let missedShortAvg = mean(missedShort),
                  let takenMediumAvg = mean(takenMedium),
                  let missedMediumAvg = mean(missedMedium) else { return nil }
            let shortDelta = takenShortAvg - missedShortAvg
            let mediumDelta = takenMediumAvg - missedMediumAvg
            let spread = standardDeviation(takenShort + missedShort + takenMedium + missedMedium)
            let uncertainty = max(0.05, min(1.0, spread / sqrt(Double(max(1, support)))))

            return MedicationTrajectory(
                medicationName: name,
                shortWindowDelta: shortDelta,
                mediumWindowDelta: mediumDelta,
                uncertainty: uncertainty,
                sampleCount: takenShort.count + missedShort.count,
                isDataSufficient: sufficient
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDataSufficient != rhs.isDataSufficient {
                return lhs.isDataSufficient && !rhs.isDataSufficient
            }
            if abs(lhs.mediumWindowDelta - rhs.mediumWindowDelta) > 0.0001 {
                return lhs.mediumWindowDelta < rhs.mediumWindowDelta
            }
            return lhs.medicationName < rhs.medicationName
        }
    }

    private static func riskScore(_ entry: MoodEntry) -> Double {
        let moodRisk = Double(abs(entry.moodLevel)) / 3.0
        let sleepRisk = max(0, (6.5 - entry.sleepHours) / 3.0)
        let activationRisk = max(0, (Double(entry.energy) - 3.0) / 2.0)
        let anxietyRisk = Double(entry.anxiety) / 3.0
        let irritabilityRisk = Double(entry.irritability) / 3.0
        return (0.35 * moodRisk) + (0.2 * sleepRisk) + (0.15 * activationRisk) + (0.15 * anxietyRisk) + (0.15 * irritabilityRisk)
    }

    private static func meanFutureRisk(
        from index: Int,
        count: Int,
        sorted: [MoodEntry],
        riskByEntryId: [ObjectIdentifier: Double]
    ) -> Double? {
        let start = index + 1
        guard start < sorted.count, count > 0 else { return nil }
        let upperBound = min(sorted.count - 1, index + count)
        guard upperBound >= start else { return nil }
        let future = sorted[start...upperBound]
        let values = future.compactMap { riskByEntryId[ObjectIdentifier($0)] }
        return mean(values)
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1, let m = mean(values) else { return 0 }
        let variance = values.reduce(0) { partial, value in
            let delta = value - m
            return partial + (delta * delta)
        } / Double(values.count - 1)
        return sqrt(variance)
    }
}
