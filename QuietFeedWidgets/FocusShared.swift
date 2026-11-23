import Foundation
#if os(iOS)
import ActivityKit
#endif

/// What the widget extension shares with the app. Keep in sync with
/// `QuietFeed/Models/FocusSurfaces.swift`: same App Group, keys and attributes.
enum FocusShared {
    static let appGroup = "group.com.kanna.quietfeed"
    static let widgetKind = "QuietFeedFocus"

    private enum Key {
        static let endDate = "focusSessionEndDate"
        static let isEnabled = "focusModeEnabled"
    }

    /// When the current session ends, if one is running.
    static func activeEndDate(now: Date = .now) -> Date? {
        let end = UserDefaults(suiteName: appGroup)?.object(forKey: Key.endDate) as? Date
        return end.flatMap { $0 > now ? $0 : nil }
    }

    /// Focus Mode is on unless the person turned it off in Settings (the app's default).
    static var isEnabled: Bool {
        UserDefaults(suiteName: appGroup)?.object(forKey: Key.isEnabled) as? Bool ?? true
    }
}

#if os(iOS)
/// The Focus Live Activity. Mirrors the app's declaration; the two must match.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
    }
}
#endif
