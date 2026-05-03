import SwiftUI

/// View modifier that gates content behind a biometric / passcode
/// challenge whenever the app foregrounds past the configured grace
/// period. No-op when the user hasn't enabled `appLockEnabled` in
/// Settings, so the unlocked path costs nothing.
struct AppLockGate: ViewModifier {
    @AppStorage(AppLockSettings.appLockEnabledKey) private var appLockEnabled: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var isLocked: Bool = false
    @State private var lastBackgroundedAt: Date?
    @State private var authPending: Bool = false

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isLocked ? 0 : 1)
                .accessibilityHidden(isLocked)

            if isLocked {
                AppLockOverlay(authPending: $authPending) {
                    Task { await tryAuthenticate() }
                }
                .transition(.opacity)
            }
        }
        .task { await appearIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: appLockEnabled) { _, enabled in
            // Toggling off should never leave the app stuck behind the
            // lock screen.
            if !enabled { isLocked = false }
        }
    }

    private func appearIfNeeded() async {
        guard appLockEnabled else { return }
        // Cold launch when the toggle is on always locks, regardless of
        // grace period. There's no "background" interval to compare
        // against on first appearance.
        isLocked = true
        await tryAuthenticate()
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        guard appLockEnabled else { return }
        switch phase {
        case .background, .inactive:
            if lastBackgroundedAt == nil { lastBackgroundedAt = Date() }
        case .active:
            let backgroundedAt = lastBackgroundedAt
            lastBackgroundedAt = nil
            guard let backgroundedAt else { return }
            let elapsed = Date().timeIntervalSince(backgroundedAt)
            if elapsed >= AppLockSettings.backgroundGraceSeconds {
                isLocked = true
                Task { await tryAuthenticate() }
            }
        @unknown default:
            break
        }
    }

    private func tryAuthenticate() async {
        guard !authPending else { return }
        authPending = true
        defer { authPending = false }
        let outcome = await AppLockService.authenticate()
        switch outcome {
        case .success:
            withAnimation(.easeOut(duration: 0.2)) { isLocked = false }
        case .cancelled, .failed, .unavailable:
            // Stay locked. The overlay's "Try again" button re-invokes.
            break
        }
    }
}

private struct AppLockOverlay: View {
    @Binding var authPending: Bool
    var onRetry: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("moodbound is locked")
                    .font(.title3.weight(.semibold))
                Text("Authenticate to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    onRetry()
                } label: {
                    if authPending {
                        ProgressView()
                    } else {
                        Label("Unlock", systemImage: "faceid")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(authPending)
                .accessibilityIdentifier("app-lock-unlock-button")
            }
            .padding(40)
        }
    }
}

extension View {
    func appLockGate() -> some View {
        modifier(AppLockGate())
    }
}
