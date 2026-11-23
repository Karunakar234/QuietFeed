import Foundation
import WebKit

/// What QuietFeed can do on one platform, derived from the same data the web view uses, so
/// the list can't drift from the code. "Depends on the site" means QuietFeed enables it but
/// the provider's website decides (DRM players, for example, often refuse Picture in Picture).
struct PlatformCapabilities {
    enum Availability: Equatable {
        case available
        case dependsOnSite
        case unavailable

        var label: String {
            switch self {
            case .available: "Available"
            case .dependsOnSite: "Depends on the site"
            case .unavailable: "Not available"
            }
        }

        var symbol: String {
            switch self {
            case .available: "checkmark.circle.fill"
            case .dependsOnSite: "questionmark.circle"
            case .unavailable: "xmark.circle"
            }
        }
    }

    struct Feature: Identifiable, Equatable {
        var id: String { title }
        let title: String
        let availability: Availability
        let note: String?
    }

    let features: [Feature]

    init(platform: Platform, filterCount: Int) {
        let isVideo = WebModel.videoPlatformIDs.contains(platform.id)
        let hasTrackButtons = TrackButtons.forPlatform(platform.id) != nil
        #if os(macOS)
        let supportsPiP = false
        #else
        let supportsPiP = isVideo
        #endif

        features = [
            Feature(title: "Filters",
                    availability: filterCount > 0 ? .available : .unavailable,
                    note: filterCount == 1 ? "1 switch" : "\(filterCount) switches"),
            Feature(title: "Full-screen video",
                    availability: isVideo ? .available : .unavailable,
                    note: nil),
            Feature(title: "Picture in Picture",
                    availability: supportsPiP ? .dependsOnSite : .unavailable,
                    note: supportsPiP ? "Starts when you leave QuietFeed during playback." : nil),
            Feature(title: "Background audio",
                    availability: .dependsOnSite,
                    note: "Playback continues when the site allows it."),
            Feature(title: "Mini-player song controls",
                    availability: hasTrackButtons ? .available : .unavailable,
                    note: nil),
            Feature(title: "Offline downloads",
                    availability: .unavailable,
                    note: "Provider content is DRM protected. Import your own audio in Settings instead.")
        ]
    }
}

/// Deletes WebKit website data stores, retrying once for stores a closing page still holds.
enum WebsiteDataCleaner {
    /// Returns the identifiers that still couldn't be removed.
    @discardableResult
    static func remove(_ identifiers: Set<UUID>) async -> [UUID] {
        var stillInUse: [UUID] = []
        for id in identifiers {
            do { try await WKWebsiteDataStore.remove(forIdentifier: id) } catch { stillInUse.append(id) }
        }
        guard !stillInUse.isEmpty else { return [] }
        try? await Task.sleep(for: .seconds(1))
        var failed: [UUID] = []
        for id in stillInUse {
            do { try await WKWebsiteDataStore.remove(forIdentifier: id) } catch { failed.append(id) }
        }
        return failed
    }
}
