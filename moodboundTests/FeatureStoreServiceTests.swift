import XCTest
@testable import moodbound

final class FeatureStoreServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testMaterializeIncludesSchemaVersion() {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 30).entries.suffix(1))
        let now = entries[0].timestamp.addingTimeInterval(3 * 3_600)

        let snapshot = FeatureStoreService.materialize(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.featureSchemaVersion, FeatureStoreService.featureSchemaVersion)
        XCTAssertEqual(snapshot.generatedAt, now)
        XCTAssertEqual(snapshot.vectors.count, 1)
    }

    func testMedAdherenceRate7dIsComputedFromWindowEvents() throws {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 2).entries)
        let medication = Medication(name: "Lithium")
        let e1 = entries[0]
        let e2 = entries[1]
        e1.medicationAdherenceEvents = []
        e2.medicationAdherenceEvents = []

        e1.medicationAdherenceEvents.append(
            MedicationAdherenceEvent(timestamp: e1.timestamp, taken: true, medication: medication, moodEntry: e1)
        )
        e2.medicationAdherenceEvents.append(
            MedicationAdherenceEvent(timestamp: e2.timestamp, taken: false, medication: medication, moodEntry: e2)
        )

        let vectors = FeatureStoreService.buildVectors(entries: [e1, e2], calendar: calendar)
        let rate = try XCTUnwrap(vectors.last?.medAdherenceRate7d)
        XCTAssertEqual(rate, 0.5, accuracy: 0.0001)
    }

    func testTriggerLoad7dIsAverageIntensity() throws {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 2).entries)
        let trigger = TriggerFactor(name: "Work Stress")
        let e1 = entries[0]
        let e2 = entries[1]
        e1.triggerEvents = []
        e2.triggerEvents = []

        e1.triggerEvents.append(
            TriggerEvent(timestamp: e1.timestamp, intensity: 3, trigger: trigger, moodEntry: e1)
        )
        e2.triggerEvents.append(
            TriggerEvent(timestamp: e2.timestamp, intensity: 1, trigger: trigger, moodEntry: e2)
        )

        let vectors = FeatureStoreService.buildVectors(entries: [e1, e2], calendar: calendar)
        let load = try XCTUnwrap(vectors.last?.triggerLoad7d)
        XCTAssertEqual(load, 2.0, accuracy: 0.0001)
    }

    func testVolatility7dUsesPopulationStandardDeviation() throws {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 2).entries)
        let e1 = entries[0]
        let e2 = entries[1]
        e1.moodLevel = -1
        e2.moodLevel = 1

        let vectors = FeatureStoreService.buildVectors(entries: [e1, e2], calendar: calendar)
        let volatility = try XCTUnwrap(vectors.last?.volatility7d)
        XCTAssertEqual(volatility, 1.0, accuracy: 0.0001)
    }

    func testCircadianDrift7dUsesWrappedHourDistance() throws {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 3).entries)
        let e1 = entries[0]
        let e2 = entries[1]
        let e3 = entries[2]
        let baselineDay = calendar.startOfDay(for: e1.timestamp)
        e1.timestamp = baselineDay.addingTimeInterval(23 * 3_600)
        e2.timestamp = baselineDay.addingTimeInterval(47 * 3_600)
        e3.timestamp = baselineDay.addingTimeInterval(49 * 3_600)
        e1.moodLevel = 0
        e2.moodLevel = 0
        e3.moodLevel = 0

        let vectors = FeatureStoreService.buildVectors(entries: [e1, e2, e3], calendar: calendar)
        let drift = try XCTUnwrap(vectors.last?.circadianDrift7d)
        XCTAssertEqual(drift, 2.0, accuracy: 0.0001)
    }

    func testProperty_VectorInvariantsHoldAcrossRandomizedRealisticScenarios() {
        var rng = LCRNG(seed: 0xC0FFEE)

        for _ in 0..<80 {
            let dayCount = Int.random(in: 8...220, using: &rng)
            let entries = RealisticMoodDatasetFactory.makeScenario(days: dayCount).entries

            // Apply sparse perturbations while preserving valid ranges.
            for entry in entries {
                if Int.random(in: 0..<12, using: &rng) == 0 {
                    entry.moodLevel = Int.random(in: -3...3, using: &rng)
                }
                if Int.random(in: 0..<12, using: &rng) == 0 {
                    entry.energy = Int.random(in: 1...5, using: &rng)
                }
                if Int.random(in: 0..<12, using: &rng) == 0 {
                    entry.sleepHours = Double.random(in: 3.5...12.0, using: &rng)
                }
            }

            let vectors = FeatureStoreService.buildVectors(entries: entries, calendar: calendar)

            XCTAssertEqual(vectors.count, entries.count)
            for pair in zip(vectors, vectors.dropFirst()) {
                XCTAssertLessThanOrEqual(pair.0.timestamp, pair.1.timestamp)
            }

            for vector in vectors {
                XCTAssertGreaterThanOrEqual(vector.moodLevel, -3.0)
                XCTAssertLessThanOrEqual(vector.moodLevel, 3.0)
                XCTAssertGreaterThanOrEqual(vector.energy, 1.0)
                XCTAssertLessThanOrEqual(vector.energy, 5.0)
                XCTAssertGreaterThanOrEqual(vector.sleepHours, 3.5)
                XCTAssertLessThanOrEqual(vector.sleepHours, 12.0)

                if let med = vector.medAdherenceRate7d {
                    XCTAssertGreaterThanOrEqual(med, 0.0)
                    XCTAssertLessThanOrEqual(med, 1.0)
                }
                if let trigger = vector.triggerLoad7d {
                    XCTAssertGreaterThanOrEqual(trigger, 0.0)
                }
                if let volatility = vector.volatility7d {
                    XCTAssertGreaterThanOrEqual(volatility, 0.0)
                }
                if let drift = vector.circadianDrift7d {
                    XCTAssertGreaterThanOrEqual(drift, 0.0)
                    XCTAssertLessThanOrEqual(drift, 12.0)
                }
            }
        }
    }
}

private struct LCRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1
        return state
    }
}
