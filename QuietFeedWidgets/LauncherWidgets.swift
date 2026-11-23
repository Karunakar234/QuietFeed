import SwiftUI
import WidgetKit

// MARK: - Timeline

struct LauncherEntry: TimelineEntry {
    let date: Date
    /// Switched-on platforms, favourites first, in the person's order.
    let platforms: [LauncherPlatform]

    /// Favourites first, then the rest, as on QuietFeed's Home.
    var favorites: [LauncherPlatform] { platforms }

    /// Most recently opened first; never-opened platforms follow in Home order.
    var recents: [LauncherPlatform] {
        platforms.enumerated().sorted { lhs, rhs in
            switch (lhs.element.lastOpenedAt, rhs.element.lastOpenedAt) {
            case let (l?, r?): l > r
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    var favoriteCount: Int { platforms.filter(\.isFavorite).count }

    /// Platforms opened in the last 7 days.
    var recentCount: Int {
        platforms.filter { ($0.lastOpenedAt ?? .distantPast) > date.addingTimeInterval(-7 * 24 * 60 * 60) }.count
    }

    static let sample = LauncherEntry(date: .now, platforms: LauncherShared.defaultPlatforms)
}

/// Every launcher widget reads the same snapshot. The app reloads them when its platform
/// settings change, so the timeline is a single entry that never expires on its own.
struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(context.isPreview ? .sample : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> LauncherEntry {
        LauncherEntry(date: .now, platforms: LauncherShared.publishedPlatforms() ?? LauncherShared.defaultPlatforms)
    }
}

// MARK: - Shared configuration

private extension WidgetConfiguration {
    func launcherDefaults() -> some WidgetConfiguration {
        self.contentMarginsDisabled()
    }
}

private struct LauncherContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .containerBackground(for: .widget) { LauncherBackground() }
            // Tapping anywhere outside an icon opens QuietFeed's Home.
            .widgetURL(LauncherShared.homeURL)
    }
}

/// Icons in a 2 × 2 grid, for the small favourites and quick-apps widgets.
private struct IconGrid: View {
    let platforms: [LauncherPlatform]

    var body: some View {
        let shown = Array(platforms.prefix(4))
        Grid(horizontalSpacing: 14, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { row in
                GridRow {
                    ForEach(shown[row..<min(row + 2, shown.count)]) { platform in
                        PlatformButton(platform: platform) { PlatformIcon(platform: platform, size: 46) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Favorite Apps (small: 4, medium: 6)

struct FavoritesWidgetView: View {
    let entry: LauncherEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LauncherContainer {
            VStack(alignment: .leading, spacing: 10) {
                LauncherHeader(title: "Favorite Apps", symbol: "star.fill", showsChevron: family != .systemSmall)
                if entry.platforms.isEmpty {
                    LauncherEmptyView()
                } else if family == .systemSmall {
                    IconGrid(platforms: entry.favorites)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(entry.favorites.prefix(6)) { platform in
                            PlatformButton(platform: platform) {
                                VStack(spacing: 6) {
                                    PlatformIcon(platform: platform, size: 44)
                                    Text(platform.name)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

struct FavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuietFeedFavorites", provider: LauncherProvider()) { entry in
            FavoritesWidgetView(entry: entry)
        }
        .configurationDisplayName("Favorite Apps")
        .description("Open your favourite platforms in QuietFeed, with your filters on.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .launcherDefaults()
    }
}

// MARK: - Quick Apps (small: 4 most recently opened)

struct QuickAppsWidgetView: View {
    let entry: LauncherEntry

    var body: some View {
        LauncherContainer {
            VStack(alignment: .leading, spacing: 10) {
                LauncherHeader(title: "Quick Apps", symbol: "bolt.fill", showsChevron: true)
                if entry.platforms.isEmpty { LauncherEmptyView() } else { IconGrid(platforms: entry.recents) }
            }
        }
    }
}

struct QuickAppsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuietFeedQuickApps", provider: LauncherProvider()) { entry in
            QuickAppsWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Apps")
        .description("The platforms you opened most recently.")
        .supportedFamilies([.systemSmall])
        .launcherDefaults()
    }
}

// MARK: - Open QuietFeed (small)

struct OpenQuietFeedWidgetView: View {
    var body: some View {
        LauncherContainer {
            VStack(spacing: 8) {
                Image(systemName: "movieclapper.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                Text("Entertainment")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "play.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(LauncherStyle.brand, in: Circle())
                    .shadow(color: Color(red: 0.62, green: 0.36, blue: 1.0).opacity(0.6), radius: 10)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open QuietFeed")
        }
    }
}

struct OpenQuietFeedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuietFeedOpen", provider: LauncherProvider()) { _ in
            OpenQuietFeedWidgetView()
        }
        .configurationDisplayName("Open QuietFeed")
        .description("One tap to your calmer entertainment hub.")
        .supportedFamilies([.systemSmall])
        .launcherDefaults()
    }
}

// MARK: - Library (small)

struct LibraryWidgetView: View {
    let entry: LauncherEntry

    var body: some View {
        LauncherContainer {
            VStack(alignment: .leading, spacing: 8) {
                LauncherHeader(title: "Library", symbol: "bookmark.fill")
                row("Favorites", symbol: "star.fill", value: entry.favoriteCount)
                row("Recent", symbol: "clock.arrow.circlepath", value: entry.recentCount)
                row("All Apps", symbol: "square.grid.2x2.fill", value: entry.platforms.count)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func row(_ title: LocalizedStringKey, symbol: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(value, format: .number)
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct LibraryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuietFeedLibrary", provider: LauncherProvider()) { entry in
            LibraryWidgetView(entry: entry)
        }
        .configurationDisplayName("Library")
        .description("Your favourites, recently opened and all platforms at a glance.")
        .supportedFamilies([.systemSmall])
        .launcherDefaults()
    }
}

// MARK: - Extended Launcher (large: 6 apps + shortcuts)

struct LauncherWidgetView: View {
    let entry: LauncherEntry

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        LauncherContainer {
            VStack(alignment: .leading, spacing: 10) {
                LauncherHeader(title: "Extended Launcher", symbol: "star.fill")
                if entry.platforms.isEmpty {
                    LauncherEmptyView()
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(entry.favorites.prefix(6)) { platform in
                            PlatformButton(platform: platform) {
                                VStack(spacing: 5) {
                                    PlatformIcon(platform: platform, size: 38)
                                    Text(platform.name)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 70)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        shortcut("Open QuietFeed", symbol: "play.fill", url: LauncherShared.homeURL)
                        shortcut("Favorites", symbol: "star.fill", url: LauncherShared.homeURL)
                    }
                    GridRow {
                        // Reopens the platform used last, the way Home's "Jump back in" does.
                        shortcut("Recently Opened", symbol: "clock.arrow.circlepath",
                                 url: entry.recents.first.map { LauncherShared.openURL($0.id) } ?? LauncherShared.homeURL)
                        shortcut("All Apps", symbol: "square.grid.2x2.fill", url: LauncherShared.homeURL)
                    }
                }
            }
        }
    }

    private func shortcut(_ title: LocalizedStringKey, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LauncherStyle.secondaryText)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct LauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuietFeedLauncher", provider: LauncherProvider()) { entry in
            LauncherWidgetView(entry: entry)
        }
        .configurationDisplayName("Extended Launcher")
        .description("Your platforms and QuietFeed shortcuts in one place.")
        .supportedFamilies([.systemLarge])
        .launcherDefaults()
    }
}

// MARK: - Previews

#Preview("Favorites small", as: .systemSmall) { FavoritesWidget() } timeline: { LauncherEntry.sample }
#Preview("Favorites medium", as: .systemMedium) { FavoritesWidget() } timeline: { LauncherEntry.sample }
#Preview("Quick Apps", as: .systemSmall) { QuickAppsWidget() } timeline: { LauncherEntry.sample }
#Preview("Open QuietFeed", as: .systemSmall) { OpenQuietFeedWidget() } timeline: { LauncherEntry.sample }
#Preview("Library", as: .systemSmall) { LibraryWidget() } timeline: { LauncherEntry.sample }
#Preview("Extended Launcher", as: .systemLarge) { LauncherWidget() } timeline: { LauncherEntry.sample }
