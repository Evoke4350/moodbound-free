import SwiftUI

/// One-shot sheet shown after an upgrade. Surfaces the WhatsNewRegistry
/// release entry for the current bundle version. Tracks
/// `whatsNewLastSeenVersion` in AppStorage so the sheet only fires
/// when the version actually changes (and never on a fresh install,
/// where there's no prior version to compare against).
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    let release: WhatsNewRelease

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's new in \(release.version)")
                            .font(.title3.weight(.bold))
                        Text(release.headline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 14) {
                        ForEach(release.highlights) { highlight in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: highlight.icon)
                                    .font(.title2)
                                    .foregroundStyle(MoodboundDesign.tint)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(highlight.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(highlight.body)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .moodCard()
                        }
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("whats-new-dismiss")
                }
            }
        }
    }
}

/// Modifier you attach near the root view; checks
/// `whatsNewLastSeenVersion` against the running bundle version and
/// presents `WhatsNewView` once per upgrade.
struct WhatsNewPresenter: ViewModifier {
    @AppStorage("whatsNewLastSeenVersion") private var lastSeenVersion: String = ""
    @State private var pendingRelease: WhatsNewRelease?

    func body(content: Content) -> some View {
        content
            .onAppear { decideToPresent() }
            .sheet(item: $pendingRelease) { release in
                WhatsNewView(release: release)
                    .onDisappear {
                        lastSeenVersion = release.version
                    }
            }
    }

    private func decideToPresent() {
        // Suppress for UI tests so existing scripts don't have to dismiss
        // the sheet on every launch. UI tests pass `-uitest` already
        // (see BackfillFlowUITests).
        if ProcessInfo.processInfo.arguments.contains("-uitest") { return }
        let current = WhatsNewRegistry.currentBundleVersion()
        // First-ever launch: record the version silently so we don't
        // greet new users with a recap of changes they never saw.
        guard !lastSeenVersion.isEmpty else {
            lastSeenVersion = current
            return
        }
        guard lastSeenVersion != current else { return }
        guard let release = WhatsNewRegistry.release(for: current) else {
            // No entry for this version — record so we don't keep
            // checking, but don't show anything.
            lastSeenVersion = current
            return
        }
        pendingRelease = release
    }
}

extension View {
    func whatsNewPresenter() -> some View {
        modifier(WhatsNewPresenter())
    }
}
