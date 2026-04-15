import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    enum AppSection: String, CaseIterable, Identifiable {
        case today
        case history
        case insights
        case rephrase

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Today"
            case .history: return "History"
            case .insights: return "Insights"
            case .rephrase: return "Rephrase"
            }
        }

        var icon: String {
            switch self {
            case .today: return "sun.max.fill"
            case .history: return "chart.xyaxis.line"
            case .insights: return "brain.head.profile"
            case .rephrase: return "bubble.left.and.bubble.right.fill"
            }
        }
    }

    @State private var selection: AppSection? = .today

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .appBackground()
        .tint(MoodboundDesign.tint)
    }

    private var compactLayout: some View {
        TabView {
            HomeView()
                .tabItem { Label("Today", systemImage: AppSection.today.icon) }

            HistoryView()
                .tabItem { Label("History", systemImage: AppSection.history.icon) }

            InsightsView()
                .tabItem { Label("Insights", systemImage: AppSection.insights.icon) }

            RephraserView()
                .tabItem { Label("Rephrase", systemImage: AppSection.rephrase.icon) }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("moodbound")
        } detail: {
            Group {
                switch selection ?? .today {
                case .today:
                    HomeView()
                case .history:
                    HistoryView()
                case .insights:
                    InsightsView()
                case .rephrase:
                    RephraserView()
                }
            }
        }
    }
}
