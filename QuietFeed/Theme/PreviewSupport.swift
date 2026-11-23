#if DEBUG
import SwiftData
import SwiftUI

/// Everything a screen needs from the app, for Xcode previews: the bundled rules, an in-memory
/// store with a settings row per platform, and stores that write to a scratch folder and
/// scratch defaults, so a preview never reads or changes the real app's data.
@MainActor
enum PreviewSupport {
    static let rules = BundledRuleProvider.loadNow()

    private static let scratchFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuietFeedPreviews", isDirectory: true)
    private static let scratchDefaults = UserDefaults(suiteName: "QuietFeedPreviews") ?? .standard

    /// An in-memory store with one settings row per platform; the first `enabledCount` are on.
    static func container(enabledCount: Int = 3) -> ModelContainer {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: PlatformSetting.self, Account.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Preview store failed: \(error)")
        }
        for (index, platform) in rules.platforms.enumerated() {
            container.mainContext.insert(
                PlatformSetting(platformID: platform.id, isEnabled: index < enabledCount, sortOrder: index))
        }
        if let first = rules.platforms.first {
            container.mainContext.insert(Account(platformID: first.id, label: "Main"))
        }
        return container
    }
}

extension View {
    /// Supplies every environment object the app's screens read, for previews only.
    func previewEnvironment(enabledCount: Int = 3) -> some View {
        self
            .environment(RuleStore(provider: BundledRuleProvider(), preloaded: PreviewSupport.rules))
            .environment(WeeklyInsightsStore(directory: PreviewSupport.scratchFolderURL))
            .environment(UsageStore(directory: PreviewSupport.scratchFolderURL))
            .environment(FocusSessionStore(defaults: PreviewSupport.scratchDefaultsStore))
            .environment(OfflineAudioLibrary(directory: PreviewSupport.scratchFolderURL))
            .environment(PlayerSession(defaults: PreviewSupport.scratchDefaultsStore))
            .environment(ConnectivityMonitor())
            .environment(AppLock(defaults: PreviewSupport.scratchDefaultsStore) { _ in .success(()) })
            .environment(IntentRouter())
            .modelContainer(PreviewSupport.container(enabledCount: enabledCount))
    }
}

extension PreviewSupport {
    static var scratchFolderURL: URL { scratchFolder }
    static var scratchDefaultsStore: UserDefaults { scratchDefaults }
}
#endif
