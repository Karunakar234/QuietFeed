import AppIntents
import Foundation
import WidgetKit

/// What the launcher widgets show: the platforms switched on in QuietFeed, favourites first,
/// in the person's order, with when each was last opened. Written to the App Group whenever
/// the platform settings change.
///
/// Mirrored in `QuietFeedWidgets/LauncherShared.swift`; keep the two in sync.
struct LauncherPlatform: Codable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let isFavorite: Bool
    let lastOpenedAt: Date?
}

enum LauncherSnapshot {
    static let platformsKey = "launcherPlatforms"
    static let pendingIDKey = "launcherPendingPlatformID"
    static let pendingAtKey = "launcherPendingAt"
    /// Every launcher widget kind, reloaded together when the snapshot changes.
    static let widgetKinds = ["QuietFeedFavorites", "QuietFeedQuickApps", "QuietFeedOpen",
                              "QuietFeedLibrary", "QuietFeedLauncher"]

    private static var shared: UserDefaults? { UserDefaults(suiteName: FocusSurfaces.appGroup) }

    /// Publishes the switched-on platforms. Only ids, names, symbols, the favourite flag and the
    /// last-opened time are shared; accounts and browsing stay in the app's own container.
    @MainActor
    static func publish(settings: [PlatformSetting], platforms: [Platform]) {
        let entries = settings
            .filter(\.isEnabled)
            .sorted { ($0.isFavorite ? 0 : 1, $0.sortOrder) < ($1.isFavorite ? 0 : 1, $1.sortOrder) }
            .compactMap { setting -> LauncherPlatform? in
                guard let platform = platforms.first(where: { $0.id == setting.platformID }) else { return nil }
                return LauncherPlatform(id: platform.id, name: platform.name, symbol: platform.symbol,
                                        isFavorite: setting.isFavorite, lastOpenedAt: setting.lastOpenedAt)
            }
        guard let data = try? JSONEncoder().encode(entries), let shared else { return }
        // Skip the write and reload when nothing changed (settings change often while browsing).
        if shared.data(forKey: platformsKey) == data { return }
        shared.set(data, forKey: platformsKey)
        for kind in widgetKinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
    }

    /// A platform a widget asked for, if the request is recent. Taken once.
    static func takePendingPlatformID(now: Date = .now) -> String? {
        guard let shared, let id = shared.string(forKey: pendingIDKey) else { return nil }
        let at = shared.object(forKey: pendingAtKey) as? Date ?? .distantPast
        shared.removeObject(forKey: pendingIDKey)
        shared.removeObject(forKey: pendingAtKey)
        return now.timeIntervalSince(at) < 30 ? id : nil
    }

    /// `quietfeed://open/<platform id>` opens a platform; any other QuietFeed URL just opens the app.
    static func platformID(from url: URL) -> String? {
        guard url.scheme == "quietfeed", url.host() == "open" else { return nil }
        let id = url.lastPathComponent
        return id.isEmpty || id == "/" ? nil : id
    }
}

/// A launcher widget's app icon. Opens QuietFeed straight into that platform, with its
/// filters on. Declared in the widget extension too (same name and parameter), so the button
/// can live in the widget while this copy runs in the app.
struct OpenPlatformFromWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Platform from Widget"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Platform ID")
    var platformID: String

    @Dependency private var router: IntentRouter

    init() {}
    init(platformID: String) { self.platformID = platformID }

    func perform() async throws -> some IntentResult {
        let id = platformID
        await MainActor.run { router.pendingPlatformID = id }
        return .result()
    }
}
