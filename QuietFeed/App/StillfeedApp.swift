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
        WindowGroup {
            RootView()
                .environment(ruleStore)
                .environment(insights)
                .tint(Theme.color.accent)
                // The neon look is designed for dark mode, so the whole app uses it.
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [PlatformSetting.self, Account.self])
    }
}
