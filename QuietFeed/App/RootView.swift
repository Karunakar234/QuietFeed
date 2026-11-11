import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(RuleStore.self) private var ruleStore
    @Environment(\.modelContext) private var context
    @Query private var settings: [PlatformSetting]
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var session = PlayerSession()

    var body: some View {
        Group {
            if !ruleStore.isLoaded {
                ProgressView().accessibilityLabel("Loading")
            } else if didOnboard {
                MainTabs()
                    // The open platform sits above the tabs, full screen or as the mini-player.
                    // It lives here rather than in a cover so shrinking it keeps the same web view playing.
                    .overlay {
                        if let platform = session.platform {
                            PlatformScreen(platform: platform, startURL: session.startURL).id(session.openID)
                        }
                    }
                    .environment(session)
            } else {
                OnboardingFlow { didOnboard = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.color.bg)
        .task {
            await ruleStore.load()
            seedSettings()
        }
    }

    /// Makes sure every platform has a settings row, so screens never meet a missing one.
    private func seedSettings() {
        let existing = Set(settings.map(\.platformID))
        for (index, platform) in ruleStore.platforms.enumerated() where !existing.contains(platform.id) {
            context.insert(PlatformSetting(platformID: platform.id, sortOrder: index))
        }
    }
}

enum AppTab: Hashable {
    case home, filters, blocking, stats, settings
}

struct MainTabs: View {
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeScreen(showFilters: { selection = .filters })
            }
            Tab("Filters", systemImage: "slider.horizontal.3", value: .filters) { FiltersScreen() }
            Tab("Blocking", systemImage: "hand.raised", value: .blocking) { BlockingScreen() }
            Tab("Stats", systemImage: "chart.bar", value: .stats) { StatsScreen() }
            Tab("Settings", systemImage: "gearshape", value: .settings) { SettingsScreen() }
        }
    }
}
