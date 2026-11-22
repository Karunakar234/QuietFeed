import SwiftData
import SwiftUI

/// One switch per filter, grouped by platform. Changes apply to an open page at once.
struct FiltersScreen: View {
    @Environment(RuleStore.self) private var ruleStore
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]
    @AppStorage("showFocusModeCard") private var showFocusModeCard = true

    private var activeSettings: [PlatformSetting] {
        settings.filter(\.isEnabled)
    }

    var body: some View {
        GlassScreen(
            title: "Filters",
            subtitle: "Shape every platform around what you actually want to see.",
            symbol: "slider.horizontal.3"
        ) {
            HomeDisplayFiltersCard(showFocusModeCard: $showFocusModeCard)

            if activeSettings.isEmpty {
                GlassSectionCard {
                    EmptyState(
                        symbol: "slider.horizontal.3",
                        title: "No platforms yet",
                        message: "Turn on a platform from Settings and its filters show up here."
                    )
                }
            } else {
                VStack(spacing: Space.s16) {
                    ForEach(activeSettings) { setting in
                        FilterPlatformCard(setting: setting)
                    }
                }
            }
        }
    }
}

private struct HomeDisplayFiltersCard: View {
    @Binding var showFocusModeCard: Bool

    var body: some View {
        GlassSectionCard("Home", symbol: "house.fill") {
            ToggleRow(
                title: "Show Focus Mode card",
                subtitle: "Display the large Focus Mode shortcut at the top of Home.",
                isOn: $showFocusModeCard
            )
            .padding(.vertical, Space.s4)
        }
    }
}

private struct FilterPlatformCard: View {
    let setting: PlatformSetting
    @Environment(RuleStore.self) private var ruleStore

    private var platformName: String {
        ruleStore.platform(id: setting.platformID)?.name ?? setting.platformID
    }

    private var toggles: [RuleToggle] {
        ruleStore.toggles(for: setting.platformID)
    }

    var body: some View {
        GlassSectionCard {
            Label(platformName, systemImage: "sparkles")
                .font(TypeRole.headline)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(toggles) { toggle in
                    ToggleRow(
                        title: toggle.title,
                        subtitle: toggle.detail,
                        isOn: Binding(
                            get: { setting.ruleToggles[toggle.key] ?? toggle.defaultOn },
                            set: { setting.ruleToggles[toggle.key] = $0 }
                        )
                    )
                    .padding(.vertical, Space.s8)

                    if toggle.id != toggles.last?.id {
                        Divider()
                            .overlay(.white.opacity(0.12))
                    }
                }
            }
        }
    }
}
