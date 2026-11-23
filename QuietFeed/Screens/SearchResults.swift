import SwiftData
import SwiftUI

/// Matching for Home's search beyond platforms and picks: filter switches and imported audio.
/// Everything searched is already on the device; nothing is sent anywhere.
enum LocalSearch {
    struct FilterMatch: Identifiable, Hashable {
        var id: String { "\(platformID).\(toggle.key)" }
        let platformID: String
        let platformName: String
        let toggle: RuleToggle
    }

    /// Filter switches whose title, detail or platform name contains `query`.
    static func filters(matching query: String, platforms: [Platform], toggles: (String) -> [RuleToggle]) -> [FilterMatch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return platforms.flatMap { platform in
            toggles(platform.id).compactMap { toggle in
                let matches = toggle.title.localizedStandardContains(query)
                    || (toggle.detail?.localizedStandardContains(query) ?? false)
                    || platform.name.localizedStandardContains(query)
                return matches ? FilterMatch(platformID: platform.id, platformName: platform.name, toggle: toggle) : nil
            }
        }
    }

    /// Imported tracks whose title contains `query`.
    static func tracks(matching query: String, in tracks: [OfflineTrack]) -> [OfflineTrack] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return tracks.filter { $0.title.localizedStandardContains(query) }
    }
}

/// Search results for filter switches (changed in place) and offline audio (played in place).
struct SearchExtras: View {
    let search: String

    @Environment(RuleStore.self) private var ruleStore
    @Environment(OfflineAudioLibrary.self) private var library
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]

    /// Only platforms on Home, so results match what the person can open.
    private var enabledPlatforms: [Platform] {
        settings.filter(\.isEnabled).compactMap { ruleStore.platform(id: $0.platformID) }
    }

    private var filterMatches: [LocalSearch.FilterMatch] {
        // A handful is enough to act on; the Filters tab has the full list.
        Array(LocalSearch.filters(matching: search, platforms: enabledPlatforms,
                                  toggles: ruleStore.toggles(for:)).prefix(8))
    }

    private var trackMatches: [OfflineTrack] {
        Array(LocalSearch.tracks(matching: search, in: library.tracks).prefix(8))
    }

    var body: some View {
        if !filterMatches.isEmpty {
            GlassSectionCard("Filters", symbol: "line.3.horizontal.decrease.circle") {
                ForEach(filterMatches) { match in
                    if let setting = settings.first(where: { $0.platformID == match.platformID }) {
                        ToggleRow(
                            title: match.toggle.title,
                            subtitle: match.platformName,
                            isOn: Binding(
                                get: { setting.ruleToggles[match.toggle.key] ?? match.toggle.defaultOn },
                                set: { setting.ruleToggles[match.toggle.key] = $0 }
                            )
                        )
                    }
                }
            }
        }
        if !trackMatches.isEmpty {
            GlassSectionCard("Offline audio", symbol: "music.note") {
                ForEach(trackMatches) { track in
                    let isCurrent = library.playingTrackID == track.id && library.isPlaying
                    Button {
                        library.togglePlayback(of: track)
                    } label: {
                        Label(track.title, systemImage: isCurrent ? "pause.circle.fill" : "play.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: Layout.minTap, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(isCurrent ? "Pause" : "Play") \(track.title)")
                }
            }
        }
    }
}
