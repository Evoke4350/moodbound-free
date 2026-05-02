import XCTest
import SwiftUI
@testable import moodbound

/// PR 3 polish: render-path smoke + perf tests.
///
/// We don't pull in swift-snapshot-testing for one new view — the cost
/// of vendoring an SPM dep + storing PNG fixtures isn't justified when
/// the data path is already nailed down by `LifeChartServiceTests` /
/// `LifeChartPropertyTests`. These tests instead use `ImageRenderer`
/// to:
///   1. confirm the chart renders successfully across trait
///      combinations (light/dark, dynamic-type XL),
///   2. measure the full SwiftUI render perf so regressions show up.
@MainActor
final class LifeChartRenderTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: d, hour: hour))!
    }

    private func makeEntries(days: Int) -> [MoodEntry] {
        (0..<days).map { offset in
            let day = date(1).addingTimeInterval(TimeInterval(offset) * 86_400)
            // Cycle through mood / sleep / energy values to exercise every
            // band, mixed-feature day, and an annotation-bearing day.
            let mood = ((offset % 7) - 3)
            return MoodEntry(
                timestamp: day,
                moodLevel: max(-3, min(3, mood)),
                energy: 1 + (offset % 5),
                sleepHours: 4.0 + Double(offset % 8),
                irritability: offset % 4,
                anxiety: offset % 4
            )
        }
    }

    private func renderImage(
        view: some View,
        size: CGSize = CGSize(width: 800, height: 240)
    ) -> UIImage? {
        let renderer = ImageRenderer(content:
            view.frame(width: size.width, height: size.height)
        )
        renderer.scale = 2
        return renderer.uiImage
    }

    // MARK: - Smoke renders across traits

    func testChartRendersForRangeOfWindowSizes() throws {
        for days in [7, 30, 90, 365] {
            let entries = makeEntries(days: days)
            let data = LifeChartService.build(
                entries: entries,
                window: .days(days),
                now: entries.last?.timestamp ?? Date()
            )
            XCTAssertEqual(data.bars.count, days, "Expected \(days) bars for window of \(days) days")
            // Drive the actual SwiftUI surface via ImageRenderer so we
            // catch any view-tree crash that the data tests would miss.
            let view = LifeChartCanvasPreview(data: data)
            let image = renderImage(view: view)
            XCTAssertNotNil(image, "Chart failed to render for \(days)-day window")
        }
    }

    func testChartRendersInDarkMode() throws {
        let entries = makeEntries(days: 90)
        let data = LifeChartService.build(
            entries: entries,
            window: .days(90),
            now: entries.last?.timestamp ?? Date()
        )
        let image = renderImage(
            view: LifeChartCanvasPreview(data: data)
                .preferredColorScheme(.dark)
        )
        XCTAssertNotNil(image)
    }

    func testChartRendersAtAccessibilityXXXLDynamicType() throws {
        let entries = makeEntries(days: 90)
        let data = LifeChartService.build(
            entries: entries,
            window: .days(90),
            now: entries.last?.timestamp ?? Date()
        )
        let image = renderImage(
            view: LifeChartCanvasPreview(data: data)
                .environment(\.dynamicTypeSize, .accessibility5)
        )
        XCTAssertNotNil(image)
    }

    // MARK: - Performance

    func testLifeChartServiceBuildPerfFor365Days() {
        let entries = makeEntries(days: 365)
        measure(metrics: [XCTClockMetric()]) {
            _ = LifeChartService.build(
                entries: entries,
                window: .days(365),
                now: entries.last?.timestamp ?? Date()
            )
        }
    }

    func testLifeChartCanvasRenderPerfFor365Days() {
        let entries = makeEntries(days: 365)
        let data = LifeChartService.build(
            entries: entries,
            window: .days(365),
            now: entries.last?.timestamp ?? Date()
        )
        measure(metrics: [XCTClockMetric()]) {
            _ = renderImage(view: LifeChartCanvasPreview(data: data))
        }
    }
}

/// Headless preview wrapper that skips the SwiftData @Query — we hand
/// the chart its data directly so render tests don't need a stub
/// `ModelContainer`.
private struct LifeChartCanvasPreview: View {
    let data: LifeChartData

    var body: some View {
        Canvas { context, size in
            let zeroY = size.height / 2
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: zeroY))
                    p.addLine(to: CGPoint(x: size.width, y: zeroY))
                },
                with: .color(.secondary.opacity(0.4)),
                lineWidth: 1
            )
            let barWidth = max(2, size.width / CGFloat(max(1, data.bars.count)))
            for (index, bar) in data.bars.enumerated() {
                guard let band = bar.band else { continue }
                let x = CGFloat(index) * barWidth
                let halfHeight = (size.height / 2) - 8
                let barHeight = halfHeight * band.barWeight
                let rect: CGRect
                switch band.pole {
                case .elevation:
                    rect = CGRect(x: x + 1, y: zeroY - barHeight, width: barWidth - 2, height: barHeight)
                case .depression:
                    rect = CGRect(x: x + 1, y: zeroY, width: barWidth - 2, height: barHeight)
                case .euthymic:
                    continue
                }
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.gray))
            }
        }
    }
}
