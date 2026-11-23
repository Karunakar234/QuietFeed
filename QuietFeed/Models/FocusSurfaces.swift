import Foundation
import WidgetKit
#if os(iOS)
import ActivityKit
#endif

/// Shows the Focus session outside the app: the Focus widget (Home Screen, Lock Screen, Mac
/// desktop) and, on iPhone and iPad, a Live Activity with the countdown.
///
/// The widget extension reads the same App Group keys and declares the same
/// `FocusActivityAttributes`; keep `QuietFeedWidgets/FocusShared.swift` in sync with this file.
enum FocusSurfaces {
    static let appGroup = "group.com.kanna.quietfeed"
    static let widgetKind = "QuietFeedFocus"

    enum Key {
        static let endDate = "focusSessionEndDate"
        static let isEnabled = "focusModeEnabled"
    }

    /// Mirrors the session into the App Group, refreshes the widget, and starts, keeps or ends
    /// the Live Activity. Only the end time and the on/off switch are shared: nothing about
    /// platforms, accounts or usage leaves the app's own container.
    @MainActor
    static func publish(endDate: Date?, isEnabled: Bool) {
        let active = isEnabled ? endDate.flatMap { $0 > .now ? $0 : nil } : nil
        if let shared = UserDefaults(suiteName: appGroup) {
            if let active { shared.set(active, forKey: Key.endDate) } else { shared.removeObject(forKey: Key.endDate) }
            shared.set(isEnabled, forKey: Key.isEnabled)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        #if os(iOS)
        Task { await updateLiveActivity(endingAt: active) }
        #endif
    }

    #if os(iOS)
    private static func updateLiveActivity(endingAt end: Date?) async {
        let running = Activity<FocusActivityAttributes>.activities
        // Already showing this session (a relaunch, say): leave it alone.
        if let end, running.count == 1, running.first?.content.state.endDate == end { return }
        for activity in running {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let end, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Stale at the end time, so the Lock Screen switches to "Focus complete" by itself.
        let content = ActivityContent(state: FocusActivityAttributes.ContentState(endDate: end), staleDate: end)
        _ = try? Activity.request(attributes: FocusActivityAttributes(), content: content)
    }
    #endif
}

#if os(iOS)
/// The Focus Live Activity. Mirrored in the widget extension; the two must match.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
    }
}
#endif
