import AppIntents
import AVFAudio
import SwiftData
import SwiftUI

@main
struct StillfeedApp: App {
    @State private var ruleStore = RuleStore(provider: BundledRuleProvider(), preloaded: BundledRuleProvider.loadNow())
    @State private var insights = WeeklyInsightsStore()
    @State private var focus: FocusSessionStore
    @State private var usage = UsageStore()
    @State private var offlineAudio = OfflineAudioLibrary()
    @State private var connectivity = ConnectivityMonitor()
    @State private var appLock = AppLock()
    @State private var intentRouter: IntentRouter

    init() {
        #if canImport(AVFAudio) && !os(macOS)
        // The playback category lets active web media continue when the app is backgrounded.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
        // Siri and Shortcuts can launch the app without any view appearing, so the stores
        // their intents use are registered here, on every launch, and shared with the UI.
        let focus = FocusSessionStore()
        let router = IntentRouter()
        _focus = State(initialValue: focus)
        _intentRouter = State(initialValue: router)
        AppDependencyManager.shared.add(dependency: focus)
        AppDependencyManager.shared.add(dependency: router)
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup("QuietFeed") {
            appRoot
                .frame(minWidth: 760, minHeight: 560)
        }
        // The app supplies its own compact 14pt header and window controls on Mac.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        .modelContainer(for: [PlatformSetting.self, Account.self])
        #else
        WindowGroup {
            appRoot
        }
        .modelContainer(for: [PlatformSetting.self, Account.self])
        #endif
    }

    private var appRoot: some View {
        RootView()
            .environment(ruleStore)
            .environment(insights)
            .environment(focus)
            .environment(usage)
            .environment(offlineAudio)
            .environment(connectivity)
            .environment(appLock)
            .environment(intentRouter)
            .tint(Theme.color.accent)
            // The appearance (System, Light or Dark) comes from Settings; RootView applies it.
    }
}
