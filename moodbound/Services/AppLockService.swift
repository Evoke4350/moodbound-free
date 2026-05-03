import Foundation
import LocalAuthentication

/// Biometric / passcode app lock. Opt-in via Settings; gated by
/// `AppLockSettings.appLockEnabled` in @AppStorage. The gate UI calls
/// `authenticate(reason:)` whenever the app foregrounds past the
/// configured grace period.
enum AppLockService {
    /// Capabilities the device exposes. Settings hides the toggle for
    /// `.unavailable` so users don't enable a feature that can't run.
    enum Capability: Equatable {
        case unavailable
        case devicePasscodeOnly
        case faceID
        case touchID
        case opticID
    }

    /// Result returned after `authenticate`. The caller decides what to
    /// do with `cancelled` vs `failed` (e.g. retry button vs surface
    /// the system error).
    enum Outcome: Equatable {
        case success
        case cancelled
        case failed(reason: String)
        case unavailable
    }

    /// Inspects the runtime device. Wraps LAContext.canEvaluatePolicy
    /// so callers don't import LocalAuthentication directly.
    static func capability(context: LAContext = LAContext()) -> Capability {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }
        // canEvaluatePolicy must succeed before biometryType is meaningful.
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        case .none: return .devicePasscodeOnly
        @unknown default: return .devicePasscodeOnly
        }
    }

    /// Prompts for biometric or passcode auth. Falls through to
    /// passcode automatically when biometric fails / is unavailable —
    /// users without Face ID can still lock with their device passcode.
    static func authenticate(
        reason: String = "Unlock moodbound",
        contextFactory: () -> LAContext = LAContext.init
    ) async -> Outcome {
        let context = contextFactory()
        var canEvaluateError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &canEvaluateError) else {
            return .unavailable
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return success ? .success : .failed(reason: "Authentication did not complete")
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .systemCancel, .appCancel:
                return .cancelled
            default:
                return .failed(reason: laError.localizedDescription)
            }
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }
}

/// Single namespace for the AppStorage keys + grace-period constants
/// the lock surface uses. Keeping this off `@AppStorage` literals makes
/// the keys greppable and the units obvious.
enum AppLockSettings {
    /// Master toggle. False by default — users must explicitly enable.
    static let appLockEnabledKey = "appLockEnabled"
    /// Seconds the app may sit in the background before re-locking. A
    /// short grace prevents Control Center / notifications from
    /// re-prompting on every pull-down.
    static let backgroundGraceSeconds: TimeInterval = 30
}
