import Foundation
import SwiftData
import SwiftUI
import UIKit

struct DailyMoodPoint: Identifiable {
    let id: Date  // startOfDay
    let averageMood: Double
}

struct ClinicianReportData {
    let range: DateInterval
    let generatedAt: Date
    let entryCount: Int
    let distinctDays: Int
    let dailyMoodPoints: [DailyMoodPoint]
    let snapshot: InsightSnapshot
    let safetyPlanText: SafetyPlanText?
    let supportContacts: [SupportContactInfo]
    let appVersion: String
}

struct SafetyPlanText {
    let warningSigns: String
    let copingStrategies: String
    let emergencySteps: String
}

struct SupportContactInfo: Identifiable {
    let id = UUID()
    let name: String
    let relationship: String
    let phone: String
    let isPrimary: Bool
}

enum ClinicianReportError: LocalizedError {
    case insufficientData(distinctDays: Int)
    case renderingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .insufficientData(let days):
            return "Only \(days) day\(days == 1 ? "" : "s") of data in this range. Need at least 7."
        case .renderingFailed(let error):
            return "Couldn't generate the PDF: \(error.localizedDescription)"
        }
    }
}

enum ClinicianReportService {
    static let minimumDistinctDays = 7

    static func snapshot(for range: DateInterval, context: ModelContext) throws -> ClinicianReportData {
        let start = range.start
        let end = range.end

        var descriptor = FetchDescriptor<MoodEntry>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp <= end },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = 10_000
        let entries = try context.fetch(descriptor)

        let calendar = Calendar.current
        let distinctDays = Set(entries.map { calendar.startOfDay(for: $0.timestamp) }).count

        guard distinctDays >= minimumDistinctDays else {
            throw ClinicianReportError.insufficientData(distinctDays: distinctDays)
        }

        // Aggregate mood by day for the chart on page 2.
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        let dailyMoodPoints = grouped.map { day, dayEntries in
            let avg = Double(dayEntries.reduce(0) { $0 + $1.moodLevel }) / Double(dayEntries.count)
            return DailyMoodPoint(id: day, averageMood: avg)
        }.sorted { $0.id < $1.id }

        let insightSnapshot = InsightEngine.snapshot(entries: entries, now: end)

        // Fetch safety plan + contacts for page 3.
        let plans = try context.fetch(FetchDescriptor<SafetyPlan>())
        let safetyPlanText: SafetyPlanText? = plans.first.flatMap { plan in
            let hasContent = !plan.warningSigns.isEmpty || !plan.copingStrategies.isEmpty || !plan.emergencySteps.isEmpty
            guard hasContent else { return nil }
            return SafetyPlanText(
                warningSigns: plan.warningSigns,
                copingStrategies: plan.copingStrategies,
                emergencySteps: plan.emergencySteps
            )
        }

        let contacts = try context.fetch(FetchDescriptor<SupportContact>(sortBy: [SortDescriptor(\.name)]))
        let contactInfos = contacts.map {
            SupportContactInfo(name: $0.name, relationship: $0.relationship, phone: $0.phone, isPrimary: $0.isPrimary)
        }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        return ClinicianReportData(
            range: range,
            generatedAt: Date(),
            entryCount: entries.count,
            distinctDays: distinctDays,
            dailyMoodPoints: dailyMoodPoints,
            snapshot: insightSnapshot,
            safetyPlanText: safetyPlanText,
            supportContacts: contactInfos,
            appVersion: "moodbound \(version) (\(build))"
        )
    }

    @MainActor
    static func render(_ data: ClinicianReportData) throws -> URL {
        let pageSize = CGSize(width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        let pdfData = renderer.pdfData { ctx in
            let pages: [any View] = [
                ReportPageOne(data: data),
                ReportPageTwo(data: data),
                ReportPageThree(data: data),
            ]

            for page in pages {
                ctx.beginPage()
                let imageRenderer = ImageRenderer(content: AnyView(page.frame(width: pageSize.width, height: pageSize.height)))
                imageRenderer.proposedSize = .init(pageSize)
                imageRenderer.render { _, drawAction in
                    // UIGraphicsPDFRenderer's CG context uses UIKit-flipped
                    // coordinates (origin top-left). ImageRenderer.render
                    // expects a CG-native context (origin bottom-left). Without
                    // this flip the page renders upside-down and mirrored.
                    let cg = ctx.cgContext
                    cg.saveGState()
                    cg.translateBy(x: 0, y: pageSize.height)
                    cg.scaleBy(x: 1, y: -1)
                    drawAction(cg)
                    cg.restoreGState()
                }
            }
        }

        let filename = "moodbound-report-\(data.range.start.formatted(.iso8601.year().month().day()))-to-\(data.range.end.formatted(.iso8601.year().month().day())).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try pdfData.write(to: url)
        return url
    }
}
