import Foundation
import HealthKit

enum HealthKitService {
    private static let store = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    /// All HealthKit types the app reads.
    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let hr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(hr) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) { types.insert(mindful) }
        return types
    }

    /// All HealthKit types the app writes.
    private static var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) { types.insert(mindful) }
        return types
    }


    /// Requests read-only access to sleep analysis data.
    static func requestSleepAuthorization() async -> Bool {
        guard isAvailable else { return false }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [sleepType])
            return true
        } catch {
            AppLogger.error("HealthKit sleep authorization failed", error: error)
            return false
        }
    }

    /// Requests access to all read + write types used by the app.
    static func requestFullAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            AppLogger.error("HealthKit full authorization failed", error: error)
            return false
        }
    }

    // MARK: - Read: Sleep

    /// Fetches total sleep hours for the most recent night.
    ///
    /// Queries `sleepAnalysis` samples from 6 PM yesterday to noon today.
    /// Only counts actual sleep stages — ignores `inBed` and `awake`.
    static func fetchLastNightSleepHours() async -> Double? {
        guard isAvailable else { return nil }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let calendar = Calendar.current
        let now = Date()
        let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        guard let yesterdayEvening = calendar.date(byAdding: .hour, value: -18, to: todayNoon) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: yesterdayEvening,
            end: todayNoon,
            options: .strictStartDate
        )

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]

        do {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: sleepType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let samples = try await descriptor.result(for: store)

            // Union the asleep intervals so overlapping samples don't get
            // counted twice. Apple Watch writes Core/REM/Deep stages, and
            // 3rd-party apps (AutoSleep, Pillow, older watchOS) often write
            // asleepUnspecified across the same window — naive summing
            // produced totals ~2x the user's actual sleep.
            let asleepIntervals = samples
                .filter { asleepValues.contains($0.value) }
                .map { ($0.startDate, $0.endDate) }
                .sorted { $0.0 < $1.0 }

            var merged: [(Date, Date)] = []
            for interval in asleepIntervals {
                if let last = merged.last, interval.0 <= last.1 {
                    merged[merged.count - 1] = (last.0, max(last.1, interval.1))
                } else {
                    merged.append(interval)
                }
            }

            let totalSeconds = merged.reduce(0.0) { sum, interval in
                sum + interval.1.timeIntervalSince(interval.0)
            }

            guard totalSeconds > 0 else { return nil }
            let hours = totalSeconds / 3600.0
            let clamped = min(max(hours, 0), 16)
            return (clamped * 2).rounded() / 2
        } catch {
            AppLogger.error("HealthKit sleep query failed", error: error)
            return nil
        }
    }

    // MARK: - Read: Heart Rate

    /// Fetches the most recent resting heart rate sample (BPM).
    static func fetchRestingHeartRate() async -> Double? {
        guard isAvailable else { return nil }
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            return nil
        }

        do {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: hrType)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: 1
            )
            let samples = try await descriptor.result(for: store)
            guard let sample = samples.first else { return nil }
            return sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        } catch {
            AppLogger.error("HealthKit resting HR query failed", error: error)
            return nil
        }
    }

    // MARK: - Read: HRV

    /// Fetches the most recent HRV SDNN value (milliseconds).
    static func fetchHRV() async -> Double? {
        guard isAvailable else { return nil }
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return nil
        }

        do {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: hrvType)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                limit: 1
            )
            let samples = try await descriptor.result(for: store)
            guard let sample = samples.first else { return nil }
            return sample.quantity.doubleValue(for: .secondUnit(with: .milli))
        } catch {
            AppLogger.error("HealthKit HRV query failed", error: error)
            return nil
        }
    }

    // MARK: - Read: Steps

    /// Fetches today's cumulative step count.
    static func fetchTodayStepCount() async -> Int? {
        guard isAvailable else { return nil }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return nil
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: .strictStartDate
        )

        do {
            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: stepType, predicate: predicate),
                options: .cumulativeSum
            )
            let result = try await descriptor.result(for: store)
            guard let sum = result?.sumQuantity() else { return nil }
            return Int(sum.doubleValue(for: .count()))
        } catch {
            AppLogger.error("HealthKit step count query failed", error: error)
            return nil
        }
    }

    // MARK: - Read: Mindful Minutes

    /// Fetches today's total mindful minutes.
    static func fetchTodayMindfulMinutes() async -> Double? {
        guard isAvailable else { return nil }
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            return nil
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: .strictStartDate
        )

        do {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: mindfulType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let samples = try await descriptor.result(for: store)
            let totalSeconds = samples.reduce(0.0) { sum, sample in
                sum + sample.endDate.timeIntervalSince(sample.startDate)
            }
            guard totalSeconds > 0 else { return nil }
            return totalSeconds / 60.0
        } catch {
            AppLogger.error("HealthKit mindful minutes query failed", error: error)
            return nil
        }
    }

    // MARK: - Write: State of Mind

    /// Writes the user's mood as an HKStateOfMind sample (iOS 18+).
    /// Maps mood level (-3...+3) to valence (-1.0...+1.0).
    @available(iOS 18.0, *)
    static func writeStateOfMind(moodLevel: Int, timestamp: Date) async {
        guard isAvailable else { return }

        let valence = Double(moodLevel) / 3.0

        let associations: [HKStateOfMind.Association] = {
            switch moodLevel {
            case -3, -2: return [.health, .selfCare]
            case -1: return [.selfCare]
            case 0: return [.selfCare]
            case 1: return [.selfCare]
            case 2, 3: return [.health, .selfCare]
            default: return [.selfCare]
            }
        }()

        let labels: [HKStateOfMind.Label] = {
            switch moodLevel {
            case -3: return [.sad, .drained]
            case -2: return [.sad]
            case -1: return [.indifferent]
            case 0: return [.peaceful]
            case 1: return [.content]
            case 2: return [.happy]
            case 3: return [.amazed, .excited]
            default: return [.peaceful]
            }
        }()

        let sample = HKStateOfMind(
            date: timestamp,
            kind: .dailyMood,
            valence: valence,
            labels: labels,
            associations: associations
        )

        do {
            try await store.save(sample)
            AppLogger.info("Wrote HKStateOfMind valence=\(valence)")
        } catch {
            AppLogger.error("Failed to write HKStateOfMind", error: error)
        }
    }

    // MARK: - Write: Mindful Session

    /// Records the check-in itself as a mindful session.
    static func writeMindfulSession(start: Date, end: Date) async {
        guard isAvailable else { return }
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            return
        }

        let sample = HKCategorySample(
            type: mindfulType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: end
        )

        do {
            try await store.save(sample)
            AppLogger.info("Wrote mindful session \(start) – \(end)")
        } catch {
            AppLogger.error("Failed to write mindful session", error: error)
        }
    }
}
