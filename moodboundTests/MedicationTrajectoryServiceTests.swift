import XCTest
@testable import moodbound

final class MedicationTrajectoryServiceTests: XCTestCase {
    func testDetectsBeneficialTrajectoryWhenTakenDaysImprove() {
        let med = Medication(name: "Lamotrigine")
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 40).entries
            .enumerated()
            .map { index, entry -> MoodEntry in
                // Taken/missed pattern is aligned with next-day risk so short-horizon trajectory is identifiable.
                let taken = index % 2 == 1
                if taken {
                    entry.moodLevel = 2
                    entry.sleepHours = 5.5
                    entry.energy = 5
                    entry.irritability = 3
                    entry.anxiety = 3
                } else {
                    entry.moodLevel = 0
                    entry.sleepHours = 7.4
                    entry.energy = 3
                    entry.irritability = 1
                    entry.anxiety = 1
                }
                let event = MedicationAdherenceEvent(
                    timestamp: entry.timestamp,
                    taken: taken,
                    medication: med,
                    moodEntry: entry
                )
                entry.medicationAdherenceEvents = [event]
                return entry
            }

        let trajectories = MedicationTrajectoryService.trajectories(entries: entries)
        let lamotrigine = try? XCTUnwrap(trajectories.first(where: { $0.medicationName == "Lamotrigine" }))
        XCTAssertNotNil(lamotrigine)
        XCTAssertTrue(lamotrigine?.isDataSufficient ?? false)
        XCTAssertLessThan(lamotrigine?.shortWindowDelta ?? 0, 0)
    }

    func testMarksInsufficientData() {
        let med = Medication(name: "Lithium")
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 10).entries
            .enumerated()
            .map { day, entry -> MoodEntry in
            let event = MedicationAdherenceEvent(
                timestamp: entry.timestamp,
                taken: day % 2 == 0,
                medication: med,
                moodEntry: entry
            )
            entry.medicationAdherenceEvents = [event]
            return entry
        }

        let trajectories = MedicationTrajectoryService.trajectories(entries: entries, minimumSamples: 8)
        XCTAssertTrue(trajectories.allSatisfy { !$0.isDataSufficient })
    }
}
