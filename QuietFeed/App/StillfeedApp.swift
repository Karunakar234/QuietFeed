import AVFAudio
import SwiftData
import SwiftUI

@main
struct StillfeedApp: App {
    @State private var ruleStore = RuleStore(provider: BundledRuleProvider())

    init() {
        // The playback category lets active web media continue when the app is backgrounded.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(ruleStore)
                .tint(Theme.color.accent)
        }
        .modelContainer(for: [PlatformSetting.self, Account.self])
    }
}
