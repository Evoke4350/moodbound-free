import SwiftData
import SwiftUI

struct SafetyPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @Query private var plans: [SafetyPlan]
    @Query(sort: \SupportContact.name) private var contacts: [SupportContact]
    @Query private var reminderSettings: [ReminderSettings]

    @State private var newContactName = ""
    @State private var newContactRelationship = ""
    @State private var newContactPhone = ""
    @State private var reminderEnabled = false
    @State private var reminderTime = Date()
    @State private var reminderMessage = L10n.tr("reminder.default_message")
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                if let plan = plans.first {
                    Section("Warning Signs") {
                        TextField("Early warning signs", text: planBinding(for: plan, keyPath: \.warningSigns))
                            .lineLimit(2...5)
                    }

                    Section("Coping Strategies") {
                        TextField("What helps you stabilize", text: planBinding(for: plan, keyPath: \.copingStrategies))
                            .lineLimit(2...5)
                    }

                    Section("Emergency Steps") {
                        TextField("Who to contact and what to do first", text: planBinding(for: plan, keyPath: \.emergencySteps))
                            .lineLimit(2...5)
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.tr("safety_plan.intro.title"))
                                .font(.headline)
                            Text(L10n.tr("safety_plan.intro.body"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        Button("Create Safety Plan") {
                            let plan = SafetyPlan()
                            context.insert(plan)
                        }
                        .accessibilityIdentifier("create-safety-plan-button")
                    }
                }

                Section {
                    ForEach(crisisResources) { resource in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(resource.name)
                                .font(.headline)
                            Text(resource.hoursNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                if !resource.phone.isEmpty {
                                    Button {
                                        call(resource.phone)
                                    } label: {
                                        Label("Call", systemImage: "phone.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("crisis-call-\(resource.regionCode)")
                                }
                                if let sms = resource.sms {
                                    Button {
                                        text(sms)
                                    } label: {
                                        Label("Text", systemImage: "bubble.left.and.bubble.right.fill")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                if let web = resource.web {
                                    Button {
                                        if let url = URL(string: web) { openURL(url) }
                                    } label: {
                                        Label("Web", systemImage: "safari.fill")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Crisis lines")
                } footer: {
                    Text("Shown for your device region. If you're traveling or these aren't right for you, the international directory can help find local support.")
                        .font(.caption)
                }

                Section("Support Contacts") {
                    ForEach(contacts) { contact in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(contact.name)
                                    .font(.headline)
                                if contact.isPrimary {
                                    Text("Primary")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundStyle(.orange)
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Button("Call") {
                                    call(contact.phone)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Call \(contact.name)")
                            }
                            Text("\(contact.relationship) • \(contact.phone)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteContacts)
                }

                Section("Add Contact") {
                    TextField("Name", text: $newContactName)
                    TextField("Relationship", text: $newContactRelationship)
                    TextField("Phone", text: $newContactPhone)
                        .keyboardType(.phonePad)

                    Button("Add Contact") {
                        addContact()
                    }
                    .disabled(newContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("add-contact-button")
                }

                Section {
                    Toggle("Enable Daily Check-In Reminder", isOn: $reminderEnabled)
                        .accessibilityIdentifier("enable-reminder-toggle")
                    DatePicker("Reminder Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .disabled(!reminderEnabled)
                    TextField("Reminder message", text: $reminderMessage)
                        .disabled(!reminderEnabled)
                    if let extras = extraReminderTimesText {
                        HStack {
                            Label("Extra times", systemImage: "clock.badge")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(extras)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Daily Reminder")
                } footer: {
                    Text("Need more than one nudge per day? After missing a few entries the home screen will offer to add extra times.")
                        .font(.caption)
                }
            }
            .navigationTitle("Safety Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndClose()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("save-safety-plan-button")
                }
            }
            .task {
                loadReminderSettingsIfNeeded()
            }
            .alert("Couldn't Save Safety Plan", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func planBinding(for plan: SafetyPlan, keyPath: ReferenceWritableKeyPath<SafetyPlan, String>) -> Binding<String> {
        Binding(
            get: { plan[keyPath: keyPath] },
            set: { newValue in
                plan[keyPath: keyPath] = newValue
                plan.updatedAt = Date()
            }
        )
    }

    private func addContact() {
        let contact = SupportContact(
            name: newContactName.trimmingCharacters(in: .whitespacesAndNewlines),
            relationship: newContactRelationship.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: newContactPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            isPrimary: contacts.isEmpty
        )
        context.insert(contact)
        newContactName = ""
        newContactRelationship = ""
        newContactPhone = ""
    }

    private func deleteContacts(at offsets: IndexSet) {
        for index in offsets {
            context.delete(contacts[index])
        }
    }

    private func call(_ phoneNumber: String) {
        let digits = phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(digits)") else { return }
        openURL(url)
    }

    private func text(_ smsNumber: String) {
        let digits = smsNumber.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "sms://\(digits)") else { return }
        openURL(url)
    }

    private var crisisResources: [CrisisResource] {
        CrisisResources.current()
    }

    private func saveAndClose() {
        do {
            syncReminderSettings()
            try context.save()
            dismiss()
        } catch {
            AppLogger.error("Failed to save safety plan", error: error)
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private var extraReminderTimesText: String? {
        guard let existing = reminderSettings.first, !existing.additionalMinutes.isEmpty else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = nil
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let formatted = existing.additionalMinutes
            .sorted()
            .compactMap { minutes -> String? in
                let h = minutes / 60
                let m = minutes % 60
                guard let date = calendar.date(bySettingHour: h, minute: m, second: 0, of: now) else { return nil }
                return formatter.string(from: date)
            }
        return formatted.joined(separator: ", ")
    }

    private func loadReminderSettingsIfNeeded() {
        if let existing = reminderSettings.first {
            reminderEnabled = existing.enabled
            reminderMessage = existing.message

            var components = DateComponents()
            components.hour = existing.hour
            components.minute = existing.minute
            reminderTime = Calendar.current.date(from: components) ?? Date()
        }
    }

    private func syncReminderSettings() {
        let settings = existingOrCreateReminderSettings()
        settings.enabled = reminderEnabled
        settings.message = reminderMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.tr("reminder.default_message")
            : reminderMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        settings.hour = components.hour ?? 20
        settings.minute = components.minute ?? 0
        settings.updatedAt = Date()

        Task {
            do {
                try await ReminderScheduler.sync(with: settings)
            } catch {
                AppLogger.error("Failed to sync reminder notifications", error: error)
            }
        }
    }

    private func existingOrCreateReminderSettings() -> ReminderSettings {
        if let existing = reminderSettings.first {
            return existing
        }
        let created = ReminderSettings()
        context.insert(created)
        return created
    }
}
