import SwiftData
import SwiftUI

/// One switch per filter, grouped by platform. Changes apply to an open page at once.
struct FiltersScreen: View {
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]
    @AppStorage("showFocusModeCard") private var showFocusModeCard = true

    private var activeSettings: [PlatformSetting] {
        settings.filter(\.isEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                ThemedSection("Home") {
                    Toggle("Show Focus Mode card", isOn: $showFocusModeCard)
                }

                if activeSettings.isEmpty {
                    ContentUnavailableView(
                        "No Platforms Enabled",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Turn on a platform in Settings to configure its filters.")
                    )
                } else {
                    ForEach(activeSettings) { setting in
                        FilterPlatformSection(setting: setting)
                    }
                }
            }
            .navigationTitle("Filters")
        }
    }
}

private struct FilterPlatformSection: View {
    let setting: PlatformSetting
    @Environment(RuleStore.self) private var ruleStore

    private var platformName: String {
        ruleStore.platform(id: setting.platformID)?.name ?? setting.platformID
    }

    private var toggles: [RuleToggle] {
        ruleStore.toggles(for: setting.platformID)
    }

    var body: some View {
        ThemedSection(verbatim: platformName) {
            ForEach(toggles) { toggle in
                Toggle(
                    isOn: Binding(
                        get: { setting.ruleToggles[toggle.key] ?? toggle.defaultOn },
                        set: { setting.ruleToggles[toggle.key] = $0 }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toggle.title)
                        if let detail = toggle.detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(Theme.color.textMuted)
                        }
                    }
                }
            }
        }
    }
}
