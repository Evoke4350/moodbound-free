import SwiftUI
import Charts

// MARK: - Page 1: Summary & Safety

struct ReportPageOne: View {
    let data: ClinicianReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reportHeader(data: data, pageNumber: 1)

            // Disclaimer
            Text("Self-reported mood data for clinical conversation. Not a diagnostic instrument. Not a substitute for professional assessment.")
                .font(.system(size: 9, design: .rounded))
                .italic()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 48)
                .padding(.top, 8)

            // Safety severity
            let safety = data.snapshot.safety
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Safety Assessment")
                HStack(spacing: 8) {
                    Text(safety.severity.rawValue)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(severityColor(safety.severity))
                    Spacer()
                    Text("Posterior risk: \(Int((safety.posteriorRisk * 100).rounded()))%")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if !safety.messages.isEmpty {
                    Text(safety.messages.joined(separator: " • "))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 16)

            // Key numbers grid
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Key Numbers")
                HStack(spacing: 0) {
                    keyNumber("Streak", "\(data.snapshot.streakDays)d")
                    keyNumber("7d Avg", data.snapshot.avg7.map { String(format: "%+.1f", $0) } ?? "—")
                    keyNumber("30d Avg", data.snapshot.avg30.map { String(format: "%+.1f", $0) } ?? "—")
                }
                HStack(spacing: 0) {
                    keyNumber("Entries", "\(data.entryCount)")
                    keyNumber("Med Adherence", data.snapshot.medicationAdherenceRate14d.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    keyNumber("Top Trigger", data.snapshot.topTrigger14d ?? "—")
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 16)

            // 7-day forecast
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("7-Day Outlook")
                let pct = Int((data.snapshot.forecastValue * 100).rounded())
                let ciLow = Int((data.snapshot.forecastCILow * 100).rounded())
                let ciHigh = Int((data.snapshot.forecastCIHigh * 100).rounded())
                Text("\(pct)% (CI \(ciLow)–\(ciHigh)%)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Conformal CI width: \(String(format: "%.2f", data.snapshot.conformalCIWidth))")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)

                // Forecast bar
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: max(0, w * CGFloat(data.snapshot.forecastCIHigh) - w * CGFloat(data.snapshot.forecastCILow)), height: 12)
                            .offset(x: w * CGFloat(data.snapshot.forecastCILow))
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 10, height: 10)
                            .offset(x: w * CGFloat(data.snapshot.forecastValue) - 5)
                    }
                }
                .frame(height: 14)
            }
            .padding(.horizontal, 48)
            .padding(.top, 16)

            // Change & drift
            VStack(alignment: .leading, spacing: 4) {
                sectionTitle("Change Detection")
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BOCPD change probability")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", data.snapshot.bayesianChangeProbability))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wasserstein drift")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", data.snapshot.wassersteinDriftScore))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 16)

            Spacer()
            reportFooter(data: data, pageNumber: 1, totalPages: 3)
        }
        .frame(width: 612, height: 792)
        .background(Color.white)
    }

    private func keyNumber(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Page 2: Trajectory & Latent State

struct ReportPageTwo: View {
    let data: ClinicianReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reportHeader(data: data, pageNumber: 2)

            // Mood chart with latent state overlay
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Mood Trajectory")
                if !data.snapshot.latentPosteriors.isEmpty {
                    moodChart
                        .frame(height: 260)
                    latentStateLegend
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 12)

            // Digital phenotype biomarkers
            if !data.snapshot.phenotypeCards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Biomarkers")
                    ForEach(data.snapshot.phenotypeCards.prefix(4)) { card in
                        HStack {
                            Text(card.title)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                            Spacer()
                            Text(card.interpretationBand)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                            Text(String(format: "(%.1f)", card.metricValue))
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 16)
            }

            // Weather impact
            if data.snapshot.weatherCoverageDays >= 7 {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Weather Impact")
                    Text("\(data.snapshot.weatherCoverageDays)-day coverage\(data.snapshot.weatherCity.map { " for \($0)" } ?? "")")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let rainy = data.snapshot.rainyMoodDelta {
                        Text("Rain effect: \(String(format: "%+.2f", rainy)) mood points")
                            .font(.system(size: 10, design: .rounded))
                    }
                    if let hot = data.snapshot.hotMoodDelta {
                        Text("Heat effect: \(String(format: "%+.2f", hot)) mood points")
                            .font(.system(size: 10, design: .rounded))
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 16)
            }

            Spacer()
            reportFooter(data: data, pageNumber: 2, totalPages: 3)
        }
        .frame(width: 612, height: 792)
        .background(Color.white)
    }

    private var moodChart: some View {
        Chart {
            // Latent state background
            ForEach(data.snapshot.latentPosteriors, id: \.timestamp) { posterior in
                RectangleMark(
                    x: .value("Day", posterior.timestamp, unit: .day),
                    yStart: .value("Low", -3),
                    yEnd: .value("High", 3)
                )
                .foregroundStyle(latentColor(posterior.distribution.dominantState).opacity(0.1))
            }
        }
        .chartYScale(domain: -3...3)
        .chartYAxis {
            AxisMarks(values: [-3, -2, -1, 0, 1, 2, 3]) { value in
                AxisGridLine()
                AxisValueLabel {
                    Text("\(value.as(Int.self) ?? 0)")
                        .font(.system(size: 8))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 8))
            }
        }
    }

    private var latentStateLegend: some View {
        HStack(spacing: 12) {
            legendItem("Depressive", .blue)
            legendItem("Stable", .green)
            legendItem("Elevated", .orange)
            legendItem("Unstable", .purple)
        }
        .font(.system(size: 8, design: .rounded))
    }

    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color.opacity(0.5)).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Page 3: Triggers, Medication & Narrative

struct ReportPageThree: View {
    let data: ClinicianReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reportHeader(data: data, pageNumber: 3)

            // Trigger attributions
            if !data.snapshot.triggerAttributions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Trigger Attributions")
                    Text("Observational associations, not causal attribution.")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(.secondary)

                    // Table header
                    HStack {
                        Text("Trigger").frame(width: 120, alignment: .leading)
                        Text("Effect").frame(width: 60, alignment: .trailing)
                        Text("Confidence").frame(width: 80, alignment: .trailing)
                        Text("Events").frame(width: 50, alignment: .trailing)
                    }
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                    ForEach(data.snapshot.triggerAttributions.prefix(5), id: \.triggerName) { attr in
                        HStack {
                            Text(attr.triggerName)
                                .lineLimit(1)
                                .frame(width: 120, alignment: .leading)
                            Text(String(format: "%+.2f", attr.score))
                                .frame(width: 60, alignment: .trailing)
                            Text("\(Int((attr.confidence * 100).rounded()))%")
                                .frame(width: 80, alignment: .trailing)
                            Text("\(attr.supportingEvents)")
                                .frame(width: 50, alignment: .trailing)
                        }
                        .font(.system(size: 9, design: .rounded))
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 12)
            }

            // Medication trajectories
            let meds = data.snapshot.medicationTrajectories.filter(\.isDataSufficient)
            if !meds.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Medication Effects")
                    Text("Compares stability on days medication was taken vs. missed.")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(.secondary)

                    ForEach(meds.prefix(3), id: \.medicationName) { med in
                        HStack {
                            Text(med.medicationName)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("Short: \(String(format: "%+.2f", med.shortWindowDelta))")
                                Text("Medium: \(String(format: "%+.2f", med.mediumWindowDelta))")
                            }
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 16)
            }

            // Narrative insights
            if !data.snapshot.narrativeCards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Narrative Insights")
                    ForEach(data.snapshot.narrativeCards.prefix(4)) { card in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                            Text(card.body)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 16)
            }

            // Safety plan
            if let plan = data.safetyPlanText {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Patient's Safety Plan")
                    if !plan.warningSigns.isEmpty {
                        planField("Warning Signs", plan.warningSigns)
                    }
                    if !plan.copingStrategies.isEmpty {
                        planField("Coping Strategies", plan.copingStrategies)
                    }
                    if !plan.emergencySteps.isEmpty {
                        planField("Emergency Steps", plan.emergencySteps)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 16)
            }

            if !data.supportContacts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Support Contacts")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    ForEach(data.supportContacts, id: \.name) { contact in
                        Text("\(contact.name)\(contact.relationship.isEmpty ? "" : " (\(contact.relationship))") — \(contact.phone)\(contact.isPrimary ? " ★" : "")")
                            .font(.system(size: 9, design: .rounded))
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 8)
            }

            Spacer()

            // Crisis banner if applicable
            if let crisisText = data.snapshot.safety.crisisBannerText {
                Text(crisisText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 48)
                    .padding(.bottom, 4)
            }

            reportFooter(data: data, pageNumber: 3, totalPages: 3)
        }
        .frame(width: 612, height: 792)
        .background(Color.white)
    }

    private func planField(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 9, design: .rounded))
        }
    }
}

// MARK: - Shared report components

private func reportHeader(data: ClinicianReportData, pageNumber: Int) -> some View {
    HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
            Text("Mood Report")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("\(data.range.start.formatted(date: .abbreviated, time: .omitted)) – \(data.range.end.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
            Text(data.appVersion)
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.secondary)
            Text("Generated \(data.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
    .padding(.horizontal, 48)
    .padding(.top, 36)
}

private func reportFooter(data: ClinicianReportData, pageNumber: Int, totalPages: Int) -> some View {
    HStack {
        Text("Generated on-device. No data left your phone.")
            .font(.system(size: 7, design: .rounded))
            .foregroundStyle(.secondary)
        Spacer()
        Text("\(pageNumber) / \(totalPages)")
            .font(.system(size: 7, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 48)
    .padding(.bottom, 24)
}

private func sectionTitle(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .padding(.top, 4)
}

private func severityColor(_ severity: SafetySeverity) -> Color {
    switch severity {
    case .none: return .green
    case .elevated: return .orange
    case .high: return .red
    case .critical: return .red
    }
}

private func latentColor(_ state: LatentMoodState) -> Color {
    switch state {
    case .depressive: return .blue
    case .stable: return .green
    case .elevated: return .orange
    case .unstable: return .purple
    }
}
