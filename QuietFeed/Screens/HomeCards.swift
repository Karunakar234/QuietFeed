import SwiftUI

/// Home's neon palette, taken from the app icon. Theme.swift is generated from design tokens,
/// so these live here rather than there.
enum Neon {
    static let teal = Color(red: 0.36, green: 0.95, blue: 0.85)
    static let violet = Color(red: 0.45, green: 0.25, blue: 0.95)
    static let blue = Color(red: 0.15, green: 0.35, blue: 0.95)
    static let magenta = Color(red: 0.85, green: 0.25, blue: 0.75)
    static let orange = Color(red: 0.98, green: 0.55, blue: 0.35)
    static let red = Color(red: 0.95, green: 0.25, blue: 0.30)
    static let navy = Color(red: 0.03, green: 0.04, blue: 0.12)
    static let deepViolet = Color(red: 0.06, green: 0.03, blue: 0.17)

    /// Teal for icons, numbers and text that sit on the screen or on glass. The bright neon
    /// teal can't be read on a light background, so Light mode uses the darker accent teal
    /// from the design tokens; Dark mode keeps the neon. Fixed dark artwork (the Focus hero,
    /// recommendation art) still uses `teal`.
    static let glow = Color.adaptive(light: Color(red: 0.055, green: 0.420, blue: 0.439), dark: teal)
}

extension Color {
    /// A colour that follows the current appearance, as the generated Theme colours do.
    static func adaptive(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #endif
    }
}

// MARK: - Background

/// The backdrop behind Home: deep navy with soft teal and violet light, like the icon.
/// In Light mode it's a pale wash with fainter glows, so dark text stays readable on it.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private var baseColors: [Color] {
        colorScheme == .dark
            ? [Neon.navy, Neon.deepViolet, Neon.navy]
            : [Color(red: 0.96, green: 0.98, blue: 0.98), Color(red: 0.96, green: 0.95, blue: 1.0),
               Color(red: 0.96, green: 0.98, blue: 0.98)]
    }

    /// Light mode keeps the same glows at under half the strength.
    private var glowScale: Double { colorScheme == .dark ? 1 : 0.4 }

    var body: some View {
        // The glows are an overlay so their fixed sizes never widen the layout: the backdrop
        // always takes exactly the space it's given, on any screen.
        LinearGradient(colors: baseColors, startPoint: .top, endPoint: .bottom)
            .overlay {
                ZStack {
                    glow(Neon.violet, opacity: 0.55 * glowScale, width: 520, height: 260, x: 140, y: -340)
                    glow(Neon.teal, opacity: 0.35 * glowScale, width: 420, height: 200, x: 200, y: -380)
                    glow(Neon.teal, opacity: 0.22 * glowScale, width: 480, height: 240, x: 190, y: 90)
                    glow(Neon.violet, opacity: 0.35 * glowScale, width: 540, height: 260, x: -170, y: 430)
                }
            }
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func glow(_ color: Color, opacity: Double, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Ellipse()
            .fill(color.opacity(opacity))
            .frame(width: width, height: height)
            .blur(radius: 100)
            .offset(x: x, y: y)
    }
}

// MARK: - Shared app screen

struct GlassScreen<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String
    let content: Content

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s24) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.color.textMuted)
                    content
                }
                .padding(.horizontal, Layout.screenPadding)
                .padding(.vertical, Space.s16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color.clear)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct GlassSectionCard<Content: View>: View {
    let title: LocalizedStringKey?
    let symbol: String?
    let content: Content

    init(
        _ title: LocalizedStringKey? = nil,
        symbol: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            if let title {
                Label(title, systemImage: symbol ?? "circle")
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Focus hero

struct FocusModeHero: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s16) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    Label("Focus Mode", systemImage: "leaf.fill")
                        .font(TypeRole.title3)
                        .foregroundStyle(.white)

                    Text("Distraction-free watching and listening")
                        .font(TypeRole.footnote)
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Space.s8)

                Image(systemName: "play.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(
                            colors: [Neon.teal, Color(red: 0.02, green: 0.55, blue: 0.56)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .overlay {
                        Circle().stroke(.white.opacity(0.55), lineWidth: 1)
                    }
                    .shadow(color: Neon.teal.opacity(0.65), radius: 16)
                    .accessibilityHidden(true)
            }
            .padding(Space.s20)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
            .background {
                FocusAuroraArtwork()
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Neon.teal.opacity(0.75), .white.opacity(0.12), Neon.violet.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Neon.teal.opacity(0.18), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus Mode")
        .accessibilityHint("Opens focus session controls")
    }
}

private struct FocusAuroraArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Neon.navy, Color(red: 0.02, green: 0.16, blue: 0.28), Neon.deepViolet],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                Ellipse()
                    .fill(Neon.teal.opacity(0.55))
                    .frame(width: proxy.size.width * 0.7, height: 80)
                    .blur(radius: 32)
                    .rotationEffect(.degrees(-10))
                    .offset(x: proxy.size.width * 0.2, y: -36)

                Ellipse()
                    .fill(Neon.violet.opacity(0.65))
                    .frame(width: proxy.size.width * 0.55, height: 72)
                    .blur(radius: 30)
                    .rotationEffect(.degrees(12))
                    .offset(x: -proxy.size.width * 0.25, y: -42)

                MountainSilhouette()
                    .fill(.black.opacity(0.48))
                    .frame(height: proxy.size.height * 0.58)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MountainSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.46))
        path.addLine(to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.width * 0.58, y: rect.height * 0.50))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.30))
        path.addLine(to: CGPoint(x: rect.width * 0.86, y: rect.height * 0.57))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Platform cards

/// How each platform's Home card looks. Home only; the rest of the app uses the plain platform data.
/// Highlights use a non-breaking space before each bullet so a wrapped line never starts with one.
struct PlatformArt {
    let highlights: String
    let iconColor: Color
    let artColors: [Color]

    static func forPlatform(_ id: String) -> PlatformArt {
        switch id {
        case "instagram":
            return PlatformArt(highlights: "Stories\u{00A0}• DMs", iconColor: Neon.magenta,
                               artColors: [Neon.magenta, Neon.orange])
        case "youtube":
            return PlatformArt(highlights: "Videos\u{00A0}• Live", iconColor: Neon.red,
                               artColors: [Neon.red, Neon.violet])
        case "youtube_music":
            return PlatformArt(highlights: "Playlists\u{00A0}• Radio", iconColor: Neon.glow,
                               artColors: [Neon.violet, Neon.blue])
        case "netflix":
            return PlatformArt(highlights: "Movies\u{00A0}• Series", iconColor: Neon.red,
                               artColors: [Neon.red, Neon.navy])
        case "amazon_prime":
            return PlatformArt(highlights: "Movies\u{00A0}• Series", iconColor: Neon.blue,
                               artColors: [Neon.blue, Neon.teal])
        case "spotify":
            return PlatformArt(highlights: "Music\u{00A0}• Playlists", iconColor: Neon.glow,
                               artColors: [Neon.teal, Neon.navy])
        default:
            return PlatformArt(highlights: "", iconColor: Neon.glow,
                               artColors: [Neon.violet, Neon.blue])
        }
    }
}

/// A compact Liquid Glass card that opens a platform: glowing icon, name and a short line of
/// highlights over a soft wash of the platform's colours. Several fit on a row, so Home shows
/// every service without much scrolling.
struct ServiceCard: View {
    let platform: Platform
    var isFavorite = false
    let action: () -> Void
    var toggleFavorite: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    private var art: PlatformArt { .forPlatform(platform.id) }
    /// The platform colour wash behind the card. Light mode uses a fainter one: at full strength
    /// the dark navy end (Netflix, Spotify) greys the card and its subtitle drops below 4.5:1.
    private var washOpacity: Double { colorScheme == .dark ? 0.35 : 0.12 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.lg, style: .continuous) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.s4) {
                Image(systemName: platform.symbol)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(art.iconColor)
                    .shadow(color: art.iconColor.opacity(0.6), radius: 8)
                    .frame(height: 36)
                    .padding(.bottom, Space.s4)
                    .accessibilityHidden(true)
                Text(platform.name)
                    .font(TypeRole.footnote.weight(.semibold))
                    .foregroundStyle(Theme.color.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(art.highlights)
                    .font(TypeRole.caption)
                    .foregroundStyle(Theme.color.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s8)
            .padding(.vertical, Space.s12)
            .frame(maxWidth: .infinity, minHeight: 108)
            .background {
                LinearGradient(colors: art.artColors.map { $0.opacity(washOpacity) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .padding(Space.s8)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(shape)
            .contentShape(shape)
            .glassEffect(.regular.interactive(), in: shape)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: toggleFavorite) {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(platform.name)
        .accessibilityValue(isFavorite ? "Favorite" : "")
        .accessibilityHint("Opens \(platform.name)")
        .accessibilityAction(named: isFavorite ? "Remove from Favorites" : "Add to Favorites", toggleFavorite)
    }
}

/// A small glass chip in Home's "Jump back in" row for a recently opened platform.
struct RecentChip: View {
    let platform: Platform
    let action: () -> Void

    private var art: PlatformArt { .forPlatform(platform.id) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s8) {
                Image(systemName: platform.symbol)
                    .foregroundStyle(art.iconColor)
                    .accessibilityHidden(true)
                Text(platform.name)
                    .font(TypeRole.footnote.weight(.semibold))
                    .foregroundStyle(Theme.color.text)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, Space.s12)
            .frame(minHeight: Layout.minTap)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(platform.name)
        .accessibilityHint("Opens \(platform.name)")
    }
}

// MARK: - Recommendations

/// A calm starting point that opens a live search on the platform, so the results are real and current.
struct Recommendation: Identifiable {
    let id: String
    let title: String
    let platformID: String
    let query: String
    let symbol: String
    let colors: [Color]

    static let all: [Recommendation] = [
        Recommendation(id: "focus", title: "Focus Mix", platformID: "youtube_music", query: "focus mix",
                       symbol: "water.waves", colors: [Neon.orange.opacity(0.8), Neon.violet]),
        Recommendation(id: "nature", title: "Nature & Travel", platformID: "youtube", query: "nature travel 4k",
                       symbol: "moon.stars.fill", colors: [Neon.blue, Neon.deepViolet]),
        Recommendation(id: "vlogs", title: "Aesthetic Vlogs", platformID: "youtube", query: "aesthetic vlog",
                       symbol: "lamp.desk.fill", colors: [Neon.magenta.opacity(0.8), Neon.navy]),
        Recommendation(id: "lofi", title: "Lo-fi Beats", platformID: "youtube_music", query: "lofi beats",
                       symbol: "headphones", colors: [Neon.teal.opacity(0.7), Neon.blue]),
    ]

    /// The platform's own search page for this pick.
    func url(for platform: Platform) -> URL? {
        var parts = URLComponents(url: platform.baseUrl, resolvingAgainstBaseURL: false)
        if platformID == "youtube_music" {
            parts?.path = "/search"
            parts?.queryItems = [URLQueryItem(name: "q", value: query)]
        } else {
            parts?.path = "/results"
            parts?.queryItems = [URLQueryItem(name: "search_query", value: query)]
        }
        return parts?.url
    }
}

struct RecommendationCard: View {
    let pick: Recommendation
    let platformName: String
    let action: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.md, style: .continuous) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    LinearGradient(colors: pick.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: pick.symbol)
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(height: 92)
                .accessibilityHidden(true)
                HStack(spacing: Space.s8) {
                    Image(systemName: "play.fill")
                        .font(TypeRole.caption.weight(.bold))
                        .foregroundStyle(Theme.color.text)
                        .frame(width: 30, height: 30)
                        .background(Theme.color.text.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pick.title)
                            .font(TypeRole.footnote.weight(.semibold))
                            .foregroundStyle(Theme.color.text)
                        Text(platformName)
                            .font(TypeRole.caption)
                            .foregroundStyle(Theme.color.textMuted)
                    }
                    .lineLimit(1)
                }
                .padding(Space.s8)
            }
            .frame(width: 156)
            .clipShape(shape)
            .contentShape(shape)
            .glassEffect(.regular.interactive(), in: shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pick.title), on \(platformName)")
        .accessibilityHint("Searches \(platformName)")
    }
}

// MARK: - Insights

struct InsightsCard: View {
    @Environment(WeeklyInsightsStore.self) private var insights

    /// Monday-first one-letter day names in the person's language.
    private var days: [String] {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return Array(symbols.dropFirst() + symbols.prefix(1))
    }

    var body: some View {
        let counts = insights.dailyCounts
        let highestCount = max(counts.max() ?? 0, 1)

        VStack(alignment: .leading, spacing: Space.s12) {
            Label {
                Text("Your Weekly Insights")
            } icon: {
                Image(systemName: "chart.bar.fill").foregroundStyle(Neon.glow)
            }
            .font(TypeRole.headline)
            .foregroundStyle(Theme.color.text)
            .accessibilityAddTraits(.isHeader)

            HStack(alignment: .bottom, spacing: Space.s16) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(insights.totalHidden, format: .number)
                        .font(TypeRole.display)
                        .foregroundStyle(Neon.glow)
                    Text("items filtered this week")
                        .font(TypeRole.footnote)
                        .foregroundStyle(Theme.color.textMuted)
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(counts.indices, id: \.self) { index in
                        VStack(spacing: Space.s4) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Neon.glow.opacity(counts[index] == 0 ? 0.18 : 0.85))
                                .frame(
                                    width: 18,
                                    height: max(4, 44 * CGFloat(counts[index]) / CGFloat(highestCount))
                                )
                            Text(days[index])
                                .font(TypeRole.caption)
                                .foregroundStyle(Theme.color.textMuted)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
                .frame(height: 64, alignment: .bottom)
                .accessibilityHidden(true)
            }
        }
        .padding(Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.lg))
        .task {
            insights.refresh()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insights.totalHidden) items filtered this week")
    }
}

#Preview("Service cards") {
    let platforms = [
        ("instagram", "Instagram", "camera"), ("youtube", "YouTube", "play.rectangle.fill"),
        ("youtube_music", "YouTube Music", "music.note"), ("netflix", "Netflix", "film"),
        ("amazon_prime", "Prime Video", "play.tv"), ("spotify", "Spotify", "waveform"),
    ].map { id, name, symbol in
        Platform(id: id, name: name, baseUrl: URL(string: "https://example.com")!, allowedHosts: [],
                 symbol: symbol, tagline: nil, isPro: false)
    }
    VStack(alignment: .leading, spacing: Space.s16) {
        WebTopBar(title: "YouTube", accountLabel: "Main", showsBack: true, onClose: {}, onMinimize: {})
        HStack(spacing: Space.s8) {
            ForEach(platforms.prefix(2)) { RecentChip(platform: $0) {} }
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Space.s12)], spacing: Space.s12) {
            ForEach(platforms) { ServiceCard(platform: $0, isFavorite: $0.id == "youtube") {} }
        }
    }
    .padding(Layout.screenPadding)
    .background { AuroraBackground() }
}
