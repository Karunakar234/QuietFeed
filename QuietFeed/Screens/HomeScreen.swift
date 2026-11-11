import SwiftData
import SwiftUI

/// S06: the launcher. One tile per platform that's switched on.
struct HomeScreen: View {
    @Environment(RuleStore.self) private var ruleStore
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]
    @State private var open: Platform?

    private var enabled: [Platform] {
        settings.filter(\.isEnabled).compactMap { ruleStore.platform(id: $0.platformID) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if enabled.isEmpty {
                    EmptyState(symbol: "square.grid.2x2", title: "Nothing here yet",
                               message: "Pick a platform to begin. You can add more later.")
                    platformSwitches
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.s12)], spacing: Space.s12) {
                        ForEach(enabled) { platform in
                            PlatformTile(name: platform.name, symbol: platform.symbol, subtitle: platform.tagline) {
                                open = platform
                            }
                        }
                    }
                    .padding(Layout.screenPadding)
                }
            }
            .background(Theme.color.bg)
            .navigationTitle("QuietFeed")
        }
        .fullScreenCover(item: $open) { platform in
            PlatformScreen(platform: platform)
        }
    }

    private var platformSwitches: some View {
        VStack(spacing: Space.s8) {
            ForEach(settings) { setting in
                if let platform = ruleStore.platform(id: setting.platformID) {
                    ToggleRow(title: platform.name, subtitle: platform.tagline, isOn: Binding(
                        get: { setting.isEnabled },
                        set: { setting.isEnabled = $0 }
                    ))
                }
            }
        }
        .padding(Layout.screenPadding)
        .frame(maxWidth: Layout.maxReadableWidth)
    }
}
