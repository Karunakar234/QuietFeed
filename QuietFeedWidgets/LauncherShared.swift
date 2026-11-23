import AppIntents
import SwiftUI
import WidgetKit

/// A switched-on platform, as the app publishes it to the App Group. Mirrors
/// `QuietFeed/Models/LauncherSnapshot.swift`; keep the two in sync.
struct LauncherPlatform: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let symbol: String
    let isFavorite: Bool
    let lastOpenedAt: Date?
}

enum LauncherShared {
    static let platformsKey = "launcherPlatforms"
    static let pendingIDKey = "launcherPendingPlatformID"
    static let pendingAtKey = "launcherPendingAt"

    /// Shown until the app has published its own list (before the first launch, say): every
    /// platform QuietFeed supports, in the app's default order.
    static let defaultPlatforms: [LauncherPlatform] = [
        ("youtube", "YouTube", "play.rectangle"), ("youtube_music", "YouTube Music", "music.note"),
        ("netflix", "Netflix", "play.tv.fill"), ("spotify", "Spotify", "music.note.list"),
        ("amazon_prime", "Prime Video", "play.square.stack.fill"), ("instagram", "Instagram", "camera"),
    ].map { LauncherPlatform(id: $0.0, name: $0.1, symbol: $0.2, isFavorite: false, lastOpenedAt: nil) }

    /// The switched-on platforms, favourites first. `nil` means the app hasn't published yet.
    static func publishedPlatforms() -> [LauncherPlatform]? {
        guard let data = UserDefaults(suiteName: FocusShared.appGroup)?.data(forKey: platformsKey) else { return nil }
        return try? JSONDecoder().decode([LauncherPlatform].self, from: data)
    }

    static func openURL(_ platformID: String) -> URL { URL(string: "quietfeed://open/\(platformID)")! }
    static let homeURL = URL(string: "quietfeed://home")!
}

/// The app icon button in a launcher widget. The app declares the same intent and runs it
/// when the system brings QuietFeed forward; this copy also leaves the request in the App
/// Group, which the app picks up when it becomes active, in case it runs here instead.
struct OpenPlatformFromWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Platform from Widget"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Platform ID")
    var platformID: String

    init() {}
    init(platformID: String) { self.platformID = platformID }

    func perform() async throws -> some IntentResult {
        let shared = UserDefaults(suiteName: FocusShared.appGroup)
        shared?.set(platformID, forKey: LauncherShared.pendingIDKey)
        shared?.set(Date.now, forKey: LauncherShared.pendingAtKey)
        return .result()
    }
}

// MARK: - Look

/// The launcher widgets' backdrop: deep navy and violet, with a soft neon wave along the
/// bottom, after QuietFeed's app icon. Fixed dark, so white text reads in both appearances.
struct LauncherBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.08, blue: 0.24), Color(red: 0.05, green: 0.05, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )
            LauncherWave()
                .fill(LinearGradient(
                    colors: [Color(red: 0.45, green: 0.25, blue: 0.95).opacity(0.55),
                             Color(red: 0.85, green: 0.25, blue: 0.75).opacity(0.35)],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 28)
                .blur(radius: 6)
        }
    }
}

private struct LauncherWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY * 0.6),
                      control1: CGPoint(x: rect.width * 0.35, y: rect.minY - 10),
                      control2: CGPoint(x: rect.width * 0.65, y: rect.maxY + 6))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Widget title row: QuietFeed's violet play tile (or another glyph) and a title.
struct LauncherHeader: View {
    let title: LocalizedStringKey
    var symbol = "play.fill"
    var showsChevron = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(LauncherStyle.brand, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

enum LauncherStyle {
    static let brand = LinearGradient(colors: [Color(red: 0.62, green: 0.36, blue: 1.0), Color(red: 0.42, green: 0.22, blue: 0.92)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Text on the dark backdrop: 0.78 white is 9:1 or better on it.
    static let secondaryText = Color.white.opacity(0.78)
}

/// A platform's icon: its brand colour behind its QuietFeed symbol. These are QuietFeed's own
/// tiles, not the services' trademarked logos.
struct PlatformIcon: View {
    let platform: LauncherPlatform
    var size: CGFloat = 40

    private var style: (background: [Color], glyph: String, glyphColor: Color) {
        switch platform.id {
        case "youtube": ([Color(red: 1.0, green: 0.16, blue: 0.16), Color(red: 0.80, green: 0.03, blue: 0.05)], "play.fill", .white)
        case "youtube_music": ([Color(red: 1.0, green: 0.20, blue: 0.22), Color(red: 0.78, green: 0.05, blue: 0.10)], "play.circle", .white)
        case "netflix": ([Color(red: 0.12, green: 0.12, blue: 0.13), .black], "play.tv.fill", Color(red: 0.90, green: 0.06, blue: 0.08))
        case "spotify": ([Color(red: 0.12, green: 0.84, blue: 0.38), Color(red: 0.08, green: 0.62, blue: 0.28)], "waveform", .black)
        case "amazon_prime": ([Color(red: 0.12, green: 0.55, blue: 1.0), Color(red: 0.05, green: 0.30, blue: 0.80)], "play.square.stack.fill", .white)
        case "instagram": ([Color(red: 1.0, green: 0.70, blue: 0.20), Color(red: 0.93, green: 0.20, blue: 0.47), Color(red: 0.55, green: 0.22, blue: 0.85)], "camera", .white)
        default: ([Color(red: 0.62, green: 0.36, blue: 1.0), Color(red: 0.42, green: 0.22, blue: 0.92)], platform.symbol, .white)
        }
    }

    var body: some View {
        let style = style
        Image(systemName: style.glyph)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(style.glyphColor)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: style.background, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

/// An icon that opens its platform in QuietFeed when tapped.
struct PlatformButton<Label: View>: View {
    let platform: LauncherPlatform
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(intent: OpenPlatformFromWidgetIntent(platformID: platform.id)) {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(platform.name)")
        .accessibilityHint("Opens it in QuietFeed with your filters on")
    }
}

/// When nothing is switched on in QuietFeed.
struct LauncherEmptyView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text("Choose platforms in QuietFeed")
                .font(.caption)
                .foregroundStyle(LauncherStyle.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
