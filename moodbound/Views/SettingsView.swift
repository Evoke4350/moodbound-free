import SwiftUI
import SwiftData
import HealthKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("healthKitSleepEnabled") private var healthKitSleepEnabled = false
    @AppStorage("healthKitFullEnabled") private var healthKitFullEnabled = false
    @AppStorage(AppLockSettings.appLockEnabledKey) private var appLockEnabled = false
    @State private var appLockCapability: AppLockService.Capability = .unavailable
    @State private var appLockEnableError: String?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingImportConfirm = false
    @State private var exportDocument: BackupDocument?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var successMessage = ""
    @State private var showingReport = false
#if DEBUG
    @State private var seeding = false
    @State private var seededCount: Int?
#endif

    var body: some View {
        NavigationStack {
            List {
                if HealthKitService.isAvailable {
                    Section {
                        Toggle(isOn: $healthKitSleepEnabled) {
                            Label("Auto-fill Sleep", systemImage: "moon.fill")
                        }
                        .onChange(of: healthKitSleepEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    let authorized = await HealthKitService.requestSleepAuthorization()
                                    if !authorized {
                                        healthKitSleepEnabled = false
                                    }
                                }
                            }
                        }

                        Toggle(isOn: $healthKitFullEnabled) {
                            Label("Full Health Integration", systemImage: "heart.fill")
                        }
                        .onChange(of: healthKitFullEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    let authorized = await HealthKitService.requestFullAuthorization()
                                    if !authorized {
                                        healthKitFullEnabled = false
                                    } else {
                                        // Full integration implies sleep too
                                        healthKitSleepEnabled = true
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Apple Health")
                    } footer: {
                        Text("Sleep auto-fills last night's hours. Full integration reads heart rate, HRV, steps, and mindful minutes, and writes your mood back to Apple Health.\n\nOura, Whoop, and similar wearables: enable Apple Health sync in their app to feed Moodbound automatically.")
                    }
                }

                Section {
                    Button {
                        showingReport = true
                    } label: {
                        Label("Share with Doctor", systemImage: "doc.richtext")
                    }
                } header: {
                    Text("Reports")
                } footer: {
                    Text("Generate a PDF summary of your mood data to bring to an appointment.")
                }

                if appLockCapability != .unavailable {
                    Section {
                        Toggle(isOn: $appLockEnabled) {
                            Label(appLockToggleLabel, systemImage: appLockIcon)
                        }
                        .onChange(of: appLockEnabled) { _, newValue in
                            if newValue {
                                Task { await verifyAppLockEnable() }
                            } else {
                                appLockEnableError = nil
                            }
                        }
                        .accessibilityIdentifier("app-lock-toggle")
                        if let appLockEnableError {
                            Text(appLockEnableError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Privacy")
                    } footer: {
                        Text("Requires \(appLockToggleLabel) when you open moodbound or return after \(Int(AppLockSettings.backgroundGraceSeconds)) seconds away.")
                    }
                }

                Section {
                    Button {
                        exportData()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingImportConfirm = true
                    } label: {
                        Label("Import Data", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Export saves all entries, medications, triggers, safety plan, daily reminders (including extra times), onboarding choices, and baseline survey responses as a JSON file. Import replaces all existing data.")
                }

#if DEBUG
                Section {
                    Button {
                        Task { await seedNinetyDays() }
                    } label: {
                        HStack {
                            if seeding { ProgressView().padding(.trailing, 4) }
                            Label(seeding ? "Seeding…" : "Seed 90 days of test data", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(seeding)
                    .accessibilityIdentifier("debug-seed-90-days")
                    if let seededCount {
                        Text("Inserted \(seededCount) entries.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Inserts realistic mood data only for days that don't already have an entry. Safe to run multiple times.")
                }
#endif
            }
            .navigationTitle("Settings")
            .task { appLockCapability = AppLockService.capability() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingReport) {
                ClinicianReportView()
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "moodbound-backup.json"
            ) { result in
                switch result {
                case .success:
                    successMessage = "Your data has been exported."
                    showingSuccess = true
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json]
            ) { result in
                importData(result: result)
            }
            .confirmationDialog(
                "Import will replace all existing data. This cannot be undone.",
                isPresented: $showingImportConfirm,
                titleVisibility: .visible
            ) {
                Button("Import and Replace", role: .destructive) {
                    showingImporter = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Export Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Success", isPresented: $showingSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(successMessage)
            }
        }
    }

    private func exportData() {
        do {
            let data = try BackupService.exportJSON(context: modelContext)
            exportDocument = BackupDocument(data: data)
            showingExporter = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

#if DEBUG
    private func seedNinetyDays() async {
        seeding = true
        defer { seeding = false }
        do {
            let inserted = try SampleDataService.insertMissingDailyEntries(
                days: 90,
                context: modelContext
            )
            seededCount = inserted
            successMessage = "Seeded \(inserted) day(s) of test data."
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
#endif

    private var appLockToggleLabel: String {
        switch appLockCapability {
        case .faceID: return "Require Face ID"
        case .touchID: return "Require Touch ID"
        case .opticID: return "Require Optic ID"
        case .devicePasscodeOnly: return "Require device passcode"
        case .unavailable: return "Require authentication"
        }
    }

    private var appLockIcon: String {
        switch appLockCapability {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.fill"
        }
    }

    /// Confirms the user can actually authenticate before locking them
    /// in. If the auth prompt fails or the user cancels, we revert the
    /// toggle so they don't lose access to the app.
    @MainActor
    private func verifyAppLockEnable() async {
        appLockEnableError = nil
        let outcome = await AppLockService.authenticate(reason: "Confirm to enable app lock")
        switch outcome {
        case .success:
            break
        case .cancelled:
            appLockEnabled = false
        case .failed(let reason):
            appLockEnabled = false
            appLockEnableError = reason
        case .unavailable:
            appLockEnabled = false
            appLockEnableError = "App lock isn't available on this device."
        }
    }

    private func importData(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw BackupServiceError.invalidBackupData
                }
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                try BackupService.importJSON(data, context: modelContext)
                successMessage = "Your data has been restored from backup."
                showingSuccess = true
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
