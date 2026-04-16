import SwiftUI
import SwiftData
import HealthKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("healthKitSleepEnabled") private var healthKitSleepEnabled = false
    @AppStorage("healthKitFullEnabled") private var healthKitFullEnabled = false
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingImportConfirm = false
    @State private var exportDocument: BackupDocument?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var successMessage = ""
    @State private var showingReport = false

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
                        Text("Sleep auto-fills last night's hours. Full integration reads heart rate, HRV, steps, and mindful minutes — and writes your mood back to Apple Health.")
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
                    Text("Export saves all entries, medications, triggers, safety plan, and settings as a JSON file. Import replaces all existing data.")
                }
            }
            .navigationTitle("Settings")
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
