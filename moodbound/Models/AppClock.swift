import Foundation

enum AppClock {
    static let overrideTimestampKey = "dev_now_timestamp"

    static var now: Date {
#if DEBUG
        let timestamp = UserDefaults.standard.double(forKey: overrideTimestampKey)
        if timestamp > 0 {
            return Date(timeIntervalSince1970: timestamp)
        }
#endif
        return Date()
    }

    static var isTimeTraveling: Bool {
#if DEBUG
        return UserDefaults.standard.double(forKey: overrideTimestampKey) > 0
#else
        return false
#endif
    }

    static func set(_ date: Date) {
#if DEBUG
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: overrideTimestampKey)
#endif
    }

    static func reset() {
#if DEBUG
        UserDefaults.standard.removeObject(forKey: overrideTimestampKey)
#endif
    }
}
