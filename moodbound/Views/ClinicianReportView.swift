import SwiftUI
import SwiftData

struct ClinicianReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var rangeOption: RangeOption = .days30
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var state: ReportState = .idle
    @State private var generateTask: Task<Void, Never>?

    enum RangeOption: String, CaseIterable, Identifiable {
        case days30 = "30 days"
        case days60 = "60 days"
        case days90 = "90 days"
        case custom = "Custom"

        var id: String { rawValue }
    }

    enum ReportState: Equatable {
        case idle
        case generating
        case ready(URL)
        case error(String)

        static func == (lhs: ReportState, rhs: ReportState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.generating, .generating): return true
            case (.ready(let a), .ready(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Range", selection: $rangeOption) {
                        ForEach(RangeOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if rangeOption == .custom {
                        DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                    }
                } header: {
                    Text("Date Range")
                }

                Section {
                    switch state {
                    case .idle:
                        Button {
                            generate()
                        } label: {
                            Label("Generate Report", systemImage: "doc.richtext")
                        }
                        .accessibilityIdentifier("generate-report-button")

                    case .generating:
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Generating report...")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Generating report")

                    case .ready(let url):
                        ShareLink(item: url, preview: SharePreview("Mood Report", image: Image(systemName: "doc.richtext"))) {
                            Label("Share Report", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            state = .idle
                        } label: {
                            Label("Generate Another", systemImage: "arrow.counterclockwise")
                        }

                    case .error(let message):
                        VStack(alignment: .leading, spacing: 8) {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(.red)

                            Button("Retry") { generate() }
                        }
                    }
                } footer: {
                    Text("Creates a PDF summary of your mood data for sharing with your doctor. Everything stays on your device.")
                }
            }
            .navigationTitle("Share with Doctor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onDisappear {
                generateTask?.cancel()
            }
        }
    }

    private var dateRange: DateInterval {
        let now = Date()
        let calendar = Calendar.current
        switch rangeOption {
        case .days30:
            return DateInterval(start: calendar.date(byAdding: .day, value: -30, to: now)!, end: now)
        case .days60:
            return DateInterval(start: calendar.date(byAdding: .day, value: -60, to: now)!, end: now)
        case .days90:
            return DateInterval(start: calendar.date(byAdding: .day, value: -90, to: now)!, end: now)
        case .custom:
            return DateInterval(start: customStart, end: customEnd)
        }
    }

    private func generate() {
        state = .generating
        generateTask = Task {
            do {
                let data = try ClinicianReportService.snapshot(for: dateRange, context: context)
                let url = try ClinicianReportService.render(data)
                state = .ready(url)
            } catch let error as ClinicianReportError {
                state = .error(error.localizedDescription ?? "Unknown error")
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }
}
