import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(RuleStore.self) private var ruleStore
    @Environment(\.modelContext) private var context
    @Query private var settings: [PlatformSetting]
    @AppStorage("didOnboard") private var didOnboard = false

    var body: some View {
        Group {
            if !ruleStore.isLoaded {
                ProgressView().accessibilityLabel("Loading")
            } else if didOnboard {
                MainTabs()
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

struct MainTabs: View {
    var body: some View {
        TabView {
            HomeScreen().tabItem { Label("Home", systemImage: "house") }
            FiltersScreen().tabItem { Label("Filters", systemImage: "slider.horizontal.3") }
            BlockingScreen().tabItem { Label("Blocking", systemImage: "hand.raised") }
            StatsScreen().tabItem { Label("Stats", systemImage: "chart.bar") }
            SettingsScreen().tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
