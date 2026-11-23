import Foundation
import SwiftData

/// One per platform: whether it's on the home screen and which filters are on.
@Model
final class PlatformSetting {
    @Attribute(.unique) var platformID: String
    var isEnabled: Bool
    var ruleToggles: [String: Bool]
    var sortOrder: Int
    /// Starred on Home; favourites sort ahead of the rest. Defaults keep existing stores migrating cleanly.
    var isFavorite: Bool = false
    /// When the platform was last opened, for Home's "Jump back in" row.
    var lastOpenedAt: Date? = nil

    init(platformID: String, isEnabled: Bool = false, ruleToggles: [String: Bool] = [:], sortOrder: Int = 0) {
        self.platformID = platformID
        self.isEnabled = isEnabled
        self.ruleToggles = ruleToggles
        self.sortOrder = sortOrder
    }
}

/// A signed-in session. `id` is also the identifier of its private website data store,
/// so each account keeps its own cookies.
@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var platformID: String
    var label: String
    var isActive: Bool
    var createdAt: Date

    init(id: UUID = UUID(), platformID: String, label: String, isActive: Bool = true, createdAt: Date = .now) {
        self.id = id
        self.platformID = platformID
        self.label = label
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
