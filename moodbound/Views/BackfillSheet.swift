import SwiftUI
import SwiftData

/// Sheet that helps a returning user catch up after missing days.
/// Two paths, picked by `MissedDayDetector`:
///   - 1..3 missed days → mass-entry form (one collapsible row per day)
///   - 4+ missed days → ask if they want check-in reminders, then collect
///     1..N times-of-day and opt them in.
struct BackfillSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var reminderSettings: [ReminderSettings]

    let recommendation: MissedDayDetector.Recommendation

    var body: some View {
        NavigationStack {
            Group {
                switch recommendation {
                case .noGap:
                    EmptyView()
                case .backfill(let days):
                    BackfillBatchEntryView(days: days) { dismiss() }
                case .offerReminders(let count):
                    BackfillReminderOptInView(
                        missingCount: count,
                        existing: reminderSettings.first
                    ) {
                        dismiss()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .accessibilityIdentifier("backfill-dismiss-button")
                }
            }
        }
    }
}

// MARK: - Mass entry (≤3 missed days)

private struct BackfillBatchEntryView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("healthKitSleepEnabled") private var healthKitSleepEnabled = false

    let days: [Date]
    var onFinished: () -> Void

    @State private var drafts: [Date: BackfillDraft] = [:]
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Quick catch-up")
                    .font(.headline)
                Text("Fill in just the basics for the day(s) you missed. Skip anything you can't remember — you can always come back and edit later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(days, id: \.self) { day in
                Section {
                    BackfillDayRow(
                        day: day,
                        draft: binding(for: day),
                        healthKitSleepEnabled: healthKitSleepEnabled
                    )
                } header: {
                    Text(headerTitle(for: day))
                }
            }

            Section {
                Button {
                    saveAll()
                } label: {
                    HStack {
                        if saving { ProgressView().padding(.trailing, 4) }
                        Text(saving ? "Saving…" : "Save \(includedDrafts.count) \(includedDrafts.count == 1 ? "day" : "days")")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                }
                .disabled(includedDrafts.isEmpty || saving)
                .accessibilityIdentifier("backfill-save-button")
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Tap a day to skip it. Saved entries land at noon on that day.")
                    .font(.caption)
            }
        }
        .navigationTitle("Catch up")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Pull HealthKit sleep for any missed day where we don't have a
            // value yet, but only when the user already opted in. This is a
            // pure assist — they can still adjust the slider.
            guard healthKitSleepEnabled else { return }
            for day in days {
                if let draft = drafts[day], draft.sleepHours > 0 { continue }
                if let hours = await HealthKitService.fetchSleepHours(morningOf: day), hours > 0 {
                    drafts[day, default: defaultDraft()].sleepHours = hours
                    drafts[day, default: defaultDraft()].sleepFromHealthKit = true
                }
            }
        }
    }

    private func defaultDraft() -> BackfillDraft {
        BackfillDraft(included: true, moodLevel: 0, energy: 3, sleepHours: 7, note: "")
    }

    private func binding(for day: Date) -> Binding<BackfillDraft> {
        Binding(
            get: { drafts[day] ?? defaultDraft() },
            set: { drafts[day] = $0 }
        )
    }

    private var includedDrafts: [(Date, BackfillDraft)] {
        days
            .compactMap { day -> (Date, BackfillDraft)? in
                let draft = drafts[day] ?? defaultDraft()
                return draft.included ? (day, draft) : nil
            }
    }

    private func headerTitle(for day: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: AppClock.now)
        let diff = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if diff == 0 { return "Today" }
        if diff == 1 { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }

    private func saveAll() {
        saving = true
        errorMessage = nil
        let calendar = Calendar.current
        do {
            for (day, draft) in includedDrafts {
                let timestamp = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
                let entry = try MoodEntry.makeValidated(
                    timestamp: timestamp,
                    moodLevel: draft.moodLevel,
                    energy: draft.energy,
                    sleepHours: draft.sleepHours,
                    irritability: 0,
                    anxiety: 0,
                    note: draft.note
                )
                context.insert(entry)
            }
            try context.save()
            saving = false
            onFinished()
        } catch {
            AppLogger.error("Backfill save failed", error: error)
            errorMessage = error.localizedDescription
            saving = false
        }
    }
}

private struct BackfillDayRow: View {
    let day: Date
    @Binding var draft: BackfillDraft
    let healthKitSleepEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Include this day", isOn: $draft.included)
                .accessibilityIdentifier("backfill-include-\(dayKey)")

            if draft.included {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mood")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    MoodSlider(value: $draft.moodLevel)
                    HStack {
                        Text(MoodScale(rawValue: draft.moodLevel)?.emoji ?? "😌")
                        Text(MoodScale(rawValue: draft.moodLevel)?.label ?? "Balanced")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Energy: \(draft.energy)/5")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Stepper(value: $draft.energy, in: 1...5) {
                        EmptyView()
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Sleep: \(String(format: "%.1f", draft.sleepHours))h")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if draft.sleepFromHealthKit {
                            Label("Apple Health", systemImage: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    Slider(value: $draft.sleepHours, in: 0...16, step: 0.5)
                }

                TextField("Note (optional)", text: $draft.note, axis: .vertical)
                    .lineLimit(1...3)
            }
        }
        .padding(.vertical, 4)
    }

    private var dayKey: String {
        ISO8601DateFormatter.dayKeyFormatter.string(from: day)
    }
}

struct BackfillDraft {
    var included: Bool
    var moodLevel: Int
    var energy: Int
    var sleepHours: Double
    var note: String
    var sleepFromHealthKit: Bool = false
}

private extension ISO8601DateFormatter {
    static let dayKeyFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}

// MARK: - Reminder opt-in (>3 missed days)

private struct BackfillReminderOptInView: View {
    @Environment(\.modelContext) private var context

    let missingCount: Int
    let existing: ReminderSettings?
    var onFinished: () -> Void

    @State private var stage: Stage = .ask
    @State private var times: [Date] = []
    @State private var saving = false
    @State private var errorMessage: String?

    enum Stage {
        case ask, configure, denied
    }

    var body: some View {
        Form {
            switch stage {
            case .ask:
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("It's been a while")
                            .font(.title3.weight(.semibold))
                        Text("You've missed \(missingCount) days. Backfilling that much from memory usually does more harm than good — the patterns get noisy. A daily nudge tends to work better.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button {
                        seedDefaultsIfNeeded()
                        stage = .configure
                    } label: {
                        Label("Set up reminders", systemImage: "bell.fill")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .accessibilityIdentifier("backfill-reminders-yes")
                    Button(role: .cancel) {
                        onFinished()
                    } label: {
                        Text("No thanks")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("backfill-reminders-no")
                }

            case .configure:
                Section {
                    Text("When should we remind you?")
                        .font(.headline)
                    Text("Pick one or more times. Two is a good starting point — once mid-day, once evening.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(times.indices, id: \.self) { index in
                        HStack {
                            DatePicker(
                                "Reminder \(index + 1)",
                                selection: Binding(
                                    get: { times[index] },
                                    set: { times[index] = $0 }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .accessibilityIdentifier("backfill-reminder-time-\(index)")
                            if times.count > 1 {
                                Button {
                                    times.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove reminder \(index + 1)")
                            }
                        }
                    }
                    if times.count < 4 {
                        Button {
                            times.append(suggestedNextTime())
                        } label: {
                            Label("Add another time", systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier("backfill-add-time")
                    }
                }
                Section {
                    Button {
                        Task { await saveAndOptIn() }
                    } label: {
                        HStack {
                            if saving { ProgressView().padding(.trailing, 4) }
                            Text(saving ? "Saving…" : "Turn on reminders")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(times.isEmpty || saving)
                    .accessibilityIdentifier("backfill-save-reminders")
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

            case .denied:
                Section {
                    Label("Notifications are off", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Text("Enable notifications for moodbound in iOS Settings to use reminders.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("OK") { onFinished() }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Stay on track")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func seedDefaultsIfNeeded() {
        guard times.isEmpty else { return }
        let calendar = Calendar.current
        let now = AppClock.now
        let noon = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: now) ?? now
        let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        if let existing, existing.enabled {
            // Preserve user's prior single time as one of the slots.
            let existingDate = calendar.date(bySettingHour: existing.hour, minute: existing.minute, second: 0, of: now) ?? noon
            times = [existingDate, evening]
        } else {
            times = [noon, evening]
        }
    }

    private func suggestedNextTime() -> Date {
        let calendar = Calendar.current
        let now = AppClock.now
        if let last = times.last,
           let bumped = calendar.date(byAdding: .hour, value: 4, to: last) {
            return bumped
        }
        return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
    }

    private func saveAndOptIn() async {
        saving = true
        errorMessage = nil
        let calendar = Calendar.current
        let allMinutes = times
            .map { date -> Int in
                let comps = calendar.dateComponents([.hour, .minute], from: date)
                return ReminderSettings.clampMinutes((comps.hour ?? 20) * 60 + (comps.minute ?? 0))
            }
            .sorted()
        guard let primary = allMinutes.first else {
            saving = false
            return
        }
        let additional = Array(allMinutes.dropFirst())
        let settings: ReminderSettings = {
            if let existing { return existing }
            let created = ReminderSettings()
            context.insert(created)
            return created
        }()
        settings.enabled = true
        settings.hour = primary / 60
        settings.minute = primary % 60
        settings.additionalMinutes = additional
        settings.updatedAt = Date()
        do {
            try context.save()
            try await ReminderScheduler.sync(with: settings)
            saving = false
            onFinished()
        } catch ReminderSchedulerError.notificationsDenied {
            settings.enabled = false
            try? context.save()
            saving = false
            stage = .denied
        } catch {
            AppLogger.error("Failed to opt in to reminders from backfill", error: error)
            errorMessage = error.localizedDescription
            saving = false
        }
    }
}
