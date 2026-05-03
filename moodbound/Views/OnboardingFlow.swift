import SwiftUI
import SwiftData
import HealthKit

/// 6-step onboarding flow shown once after first install. Order:
/// welcome → diagnosis → ASRM baseline → PHQ-2 baseline → daily
/// reminder → permissions → done. Every step except welcome and done
/// is skippable so users who hit "Skip" still land in a usable app.
///
/// The full flow persists:
/// - `OnboardingState` with `hasCompleted = true` so we never show
///   the flow twice
/// - Two `SurveyResponseRecord` rows (one per baseline survey) so
///   Phase-2 periodic re-administration can compare against install
/// - Optional `ReminderSettings` if the user picked a daily nudge time
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    enum Stage: Int, CaseIterable {
        case welcome
        case diagnosis
        case asrm
        case phq2
        case reminder
        case permissions
        case done
    }

    @State private var stage: Stage = .welcome
    @State private var diagnosis: DiagnosisSelfReport?
    @State private var asrmAnswers: [String: Int] = [:]
    @State private var phq2Answers: [String: Int] = [:]
    @State private var reminderTime: Date = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now) ?? .now
    @State private var reminderOptIn: Bool = false
    @State private var savingError: String?
    @State private var saving: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                stageContent
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                navigationFooter
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if stage != .welcome && stage != .done {
                        Button("Skip") { advance() }
                            .accessibilityIdentifier("onboarding-skip")
                    }
                }
            }
        }
    }

    // MARK: - Progress / footer

    private var progressBar: some View {
        let total = Stage.allCases.count - 1
        let current = stage.rawValue
        return ProgressView(value: Double(current), total: Double(total))
            .tint(MoodboundDesign.tint)
            .padding(.horizontal, 20)
            .padding(.top, 12)
    }

    private var navigationFooter: some View {
        HStack {
            if stage != .welcome && stage != .done {
                Button("Back") { goBack() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("onboarding-back")
            }
            Spacer()
            Button(primaryButtonLabel) {
                if stage == .done {
                    finish()
                } else {
                    advance()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(MoodboundDesign.tint)
            .disabled(saving)
            .accessibilityIdentifier("onboarding-next")
        }
    }

    private var primaryButtonLabel: String {
        switch stage {
        case .welcome: return "Get started"
        case .done: return saving ? "Saving…" : "Open moodbound"
        default: return "Continue"
        }
    }

    // MARK: - Stage content

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .welcome: welcomeStage
        case .diagnosis: diagnosisStage
        case .asrm: surveyStage(kind: .asrm, answers: $asrmAnswers)
        case .phq2: surveyStage(kind: .phq2, answers: $phq2Answers)
        case .reminder: reminderStage
        case .permissions: permissionsStage
        case .done: doneStage
        }
    }

    private var welcomeStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "heart.text.clipboard")
                    .font(.largeTitle)
                    .foregroundStyle(MoodboundDesign.tint)
                Text("Welcome")
                    .font(.title.weight(.bold))
                Text("Moodbound is a personal companion for tracking mood, sleep, and the patterns that connect them. Two minutes of setup helps the app stop guessing about your baseline.")
                    .font(.body)
                bullet("Quick check-ins, once or twice a day.")
                bullet("Patterns surface as soon as you've logged about a week.")
                bullet("Your data stays on your device unless you choose to export it.")
                Text("This is a personal tracking tool, not a substitute for professional care.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diagnosisStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Where you're starting from")
                    .font(.title2.weight(.bold))
                Text("Optional. Helps us tune what you see in Insights — never shared.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(DiagnosisSelfReport.allCases) { option in
                    Button {
                        diagnosis = option
                    } label: {
                        HStack {
                            Text(option.label)
                            Spacer()
                            if diagnosis == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(MoodboundDesign.tint)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(diagnosis == option ? MoodboundDesign.tint.opacity(0.1) : Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("diagnosis-\(option.rawValue)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func surveyStage(kind: SurveyKind, answers: Binding<[String: Int]>) -> some View {
        let definition = SurveyCatalog.definition(for: kind)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(definition.title).font(.title2.weight(.bold))
                Text(definition.intro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(definition.questions) { question in
                    SurveyQuestionRow(
                        question: question,
                        selection: Binding(
                            get: { answers.wrappedValue[question.id] },
                            set: { answers.wrappedValue[question.id] = $0 }
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reminderStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Daily check-in nudge")
                    .font(.title2.weight(.bold))
                Text("A single notification helps the app stay useful past the first week. You can change or remove it anytime in Safety Plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Toggle("Send me a daily nudge", isOn: $reminderOptIn)
                    .accessibilityIdentifier("onboarding-reminder-toggle")
                if reminderOptIn {
                    DatePicker(
                        "Time",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var permissionsStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connect Apple Health")
                    .font(.title2.weight(.bold))
                Text("Optional. If you grant access, moodbound auto-fills last night's sleep and reads recent heart rate / HRV / steps to enrich your check-ins. You can decide later in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { _ = await HealthKitService.requestSleepAuthorization() }
                } label: {
                    Label("Allow sleep auto-fill", systemImage: "moon.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(MoodboundDesign.tint)
                .accessibilityIdentifier("onboarding-allow-health")
                Text("You'll see the iOS permission prompt on tap. Skip and configure later if you'd rather try the app first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var doneStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("You're set")
                    .font(.title.weight(.bold))
                Text("Your first check-in is on the Today tab. Insights unlock once you've logged about three days; the Life Chart shows up after a week.")
                    .font(.body)
                if let asrm = asrmScore {
                    summaryCard(title: "ASRM baseline", value: "\(asrm.total) — \(asrm.band)")
                }
                if let phq2 = phq2Score {
                    summaryCard(title: "PHQ-2 baseline", value: "\(phq2.total) — \(phq2.band)")
                }
                if let savingError {
                    Text(savingError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(MoodboundDesign.tint)
                .padding(.top, 7)
            Text(text).font(.subheadline)
        }
    }

    // MARK: - Navigation + persistence

    private func advance() {
        guard let next = Stage(rawValue: stage.rawValue + 1) else { return }
        stage = next
    }

    private func goBack() {
        guard let prev = Stage(rawValue: stage.rawValue - 1), prev.rawValue >= 0 else { return }
        stage = prev
    }

    private var asrmScore: SurveyScore? {
        asrmAnswers.isEmpty ? nil : SurveyScorer.score(kind: .asrm, responses: asrmAnswers)
    }

    private var phq2Score: SurveyScore? {
        phq2Answers.isEmpty ? nil : SurveyScorer.score(kind: .phq2, responses: phq2Answers)
    }

    private func finish() {
        saving = true
        savingError = nil
        do {
            try OnboardingPersistence.persist(
                context: context,
                diagnosis: diagnosis,
                asrmAnswers: asrmAnswers,
                phq2Answers: phq2Answers,
                reminderOptIn: reminderOptIn,
                reminderTime: reminderTime
            )
            saving = false
            dismiss()
        } catch {
            AppLogger.error("Onboarding persistence failed", error: error)
            savingError = error.localizedDescription
            saving = false
        }
    }
}

private struct SurveyQuestionRow: View {
    let question: SurveyQuestion
    @Binding var selection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.prompt).font(.subheadline.weight(.semibold))
            ForEach(0...question.maxValue, id: \.self) { value in
                Button {
                    selection = value
                } label: {
                    HStack {
                        Image(systemName: selection == value ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selection == value ? MoodboundDesign.tint : .secondary)
                        Text(question.answerLabels[value])
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(question.id)-answer-\(value)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pure persistence helper so unit tests can verify side-effects
/// without standing up a SwiftUI host.
enum OnboardingPersistence {
    static func persist(
        context: ModelContext,
        diagnosis: DiagnosisSelfReport?,
        asrmAnswers: [String: Int],
        phq2Answers: [String: Int],
        reminderOptIn: Bool,
        reminderTime: Date,
        calendar: Calendar = .current,
        now: Date = .now
    ) throws {
        let state = try existingOrCreateState(context: context)
        state.hasCompleted = true
        state.completedAt = now
        state.diagnosisRawValue = diagnosis?.rawValue

        let comps = calendar.dateComponents([.hour, .minute], from: reminderTime)
        state.reminderOptedIn = reminderOptIn
        state.reminderHour = comps.hour ?? 20
        state.reminderMinute = comps.minute ?? 0

        if !asrmAnswers.isEmpty {
            let score = SurveyScorer.score(kind: .asrm, responses: asrmAnswers)
            context.insert(SurveyResponseRecord(kind: .asrm, score: score, answers: asrmAnswers, completedAt: now))
        }
        if !phq2Answers.isEmpty {
            let score = SurveyScorer.score(kind: .phq2, responses: phq2Answers)
            context.insert(SurveyResponseRecord(kind: .phq2, score: score, answers: phq2Answers, completedAt: now))
        }

        var remindersToSync: ReminderSettings?
        if reminderOptIn {
            let reminders = try existingOrCreateReminderSettings(context: context)
            reminders.enabled = true
            reminders.hour = state.reminderHour
            reminders.minute = state.reminderMinute
            reminders.updatedAt = now
            remindersToSync = reminders
        }

        try context.save()

        // Schedule on the main actor so we never touch the SwiftData
        // model object from a background actor. ReminderScheduler.sync
        // is async and yields off main while it talks to
        // UNUserNotificationCenter, but the property reads stay on main.
        if let remindersToSync {
            Task { @MainActor in
                try? await ReminderScheduler.sync(with: remindersToSync)
            }
        }
    }

    static func existingOrCreateState(context: ModelContext) throws -> OnboardingState {
        if let existing = try context.fetch(FetchDescriptor<OnboardingState>()).first {
            return existing
        }
        let created = OnboardingState()
        context.insert(created)
        return created
    }

    private static func existingOrCreateReminderSettings(context: ModelContext) throws -> ReminderSettings {
        if let existing = try context.fetch(FetchDescriptor<ReminderSettings>()).first {
            return existing
        }
        let created = ReminderSettings()
        context.insert(created)
        return created
    }
}
