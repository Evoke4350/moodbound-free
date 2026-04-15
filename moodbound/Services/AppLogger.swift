import Foundation
import OSLog

enum AppLogger {
    private static let logger = Logger(subsystem: "com.moodbound.app", category: "app")

    static func info(_ message: String) {
        logger.log(level: .info, "\(message, privacy: .public)")
    }

    static func error(_ message: String, error: Error? = nil) {
        if let error {
            logger.error("\(message, privacy: .public) | error: \(String(describing: error), privacy: .public)")
        } else {
            logger.error("\(message, privacy: .public)")
        }
    }
}
