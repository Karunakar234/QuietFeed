import SwiftData
import SwiftUI

/// S12: one switch per filter, grouped by platform. Changes apply to an open page at once.
struct FiltersScreen: View {
    @Environment(RuleStore.self) private var ruleStore
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]

    private var active: [PlatformSetting] { settings.filter(\.isEnabled) }

    var body: some View {
        NavigationStack {
            Group {
                if active.isEmpty {
                    EmptyState(symbol: "slider.horizontal.3", title: "No platforms yet",
                               message: "Turn on a platform from Home and its filters show up here.")
                } else {
                    List {
                        ForEach(active) { setting in
                            Section(ruleStore.platform(id: setting.platformID)?.name ?? setting.platformID) {
                                ForEach(ruleStore.toggles(for: setting.platformID)) { toggle in
                                    ToggleRow(title: toggle.title, subtitle: toggle.detail, isOn: Binding(
                                        get: { setting.ruleToggles[toggle.key] ?? toggle.defaultOn },
                                        set: { setting.ruleToggles[toggle.key] = $0 }
                                    ))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
        }
    }
}
