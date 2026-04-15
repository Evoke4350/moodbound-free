import Foundation
import SwiftData

@Model
final class SafetyPlan {
    var warningSigns: String
    var copingStrategies: String
    var emergencySteps: String
    var updatedAt: Date

    init(
        warningSigns: String = "",
        copingStrategies: String = "",
        emergencySteps: String = "",
        updatedAt: Date = .now
    ) {
        self.warningSigns = warningSigns
        self.copingStrategies = copingStrategies
        self.emergencySteps = emergencySteps
        self.updatedAt = updatedAt
    }
}

@Model
final class SupportContact {
    var name: String
    var relationship: String
    var phone: String
    var isPrimary: Bool

    init(
        name: String,
        relationship: String = "",
        phone: String,
        isPrimary: Bool = false
    ) {
        self.name = name
        self.relationship = relationship
        self.phone = phone
        self.isPrimary = isPrimary
    }
}
