import SwiftUI
import SwiftData

@main
struct moodboundApp: App {
    private let container: ModelContainer
    @State private var showingDisclaimer = true

    init() {
        do {
            container = try ModelContainer(
                for: MoodEntry.self,
                Medication.self,
                MedicationAdherenceEvent.self,
                TriggerFactor.self,
                TriggerEvent.self,
                SafetyPlan.self,
                SupportContact.self,
                ReminderSettings.self
            )
        } catch {
            AppLogger.error("Failed to create model container", error: error)
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .opacity(showingDisclaimer ? 0 : 1)
                    .whatsNewPresenter()

                if showingDisclaimer {
                    DisclaimerSplashView {
                        showingDisclaimer = false
                    }
                }
            }
        }
        .modelContainer(container)
    }
}
