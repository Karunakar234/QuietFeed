import AVFAudio
import SwiftData
import SwiftUI

@main
struct StillfeedApp: App {
    @State private var ruleStore = RuleStore(provider: BundledRuleProvider())
    @State private var insights = WeeklyInsightsStore()

    init() {
        #if canImport(AVFAudio) && !os(macOS)
        // The playback category lets active web media continue when the app is backgrounded.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
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
            .tint(Theme.color.accent)
            // The neon look is designed for dark mode, so the whole app uses it.
            .preferredColorScheme(.dark)
    }
}
