import SwiftUI
import SwiftData

@main
struct moodboundApp: App {
    private let container: ModelContainer
    @State private var showingDisclaimer = true
    @State private var showingOnboarding = false

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
                ReminderSettings.self,
                OnboardingState.self,
                SurveyResponseRecord.self
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
                    .appLockGate()
                    .sheet(isPresented: $showingOnboarding) {
                        OnboardingFlow()
                            .interactiveDismissDisabled()
                    }
                    .task {
                        // Decide once after disclaimer dismiss whether
                        // to present onboarding. Reads OnboardingState
                        // from the container; absence or hasCompleted
                        // == false triggers the flow.
                        guard !showingDisclaimer else { return }
                        showingOnboarding = needsOnboarding()
                    }
                    .onChange(of: showingDisclaimer) { _, dismissed in
                        if !dismissed {
                            showingOnboarding = needsOnboarding()
                        }
                    }

                if showingDisclaimer {
                    DisclaimerSplashView {
                        showingDisclaimer = false
                    }
                }
            }
        }
        .modelContainer(container)
    }

    /// Reads `OnboardingState` from the container at runtime and
    /// returns `true` if the user hasn't completed the flow. Done
    /// imperatively rather than via @Query because we need a one-shot
    /// decision before any view appears.
    @MainActor
    private func needsOnboarding() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitest-skip-onboarding") { return false }
        if args.contains("-uitest-reset-onboarding") {
            resetOnboardingForUITest()
            return true
        }
        let context = container.mainContext
        do {
            let states = try context.fetch(FetchDescriptor<OnboardingState>())
            return !(states.first?.hasCompleted ?? false)
        } catch {
            AppLogger.error("Failed to read OnboardingState", error: error)
            return false
        }
    }

    @MainActor
    private func resetOnboardingForUITest() {
        let context = container.mainContext
        do {
            let existing = try context.fetch(FetchDescriptor<OnboardingState>())
            for state in existing { context.delete(state) }
            try context.save()
        } catch {
            AppLogger.error("Failed to reset onboarding state", error: error)
        }
    }
}
