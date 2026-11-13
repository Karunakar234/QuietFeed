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
}

// MARK: - Background

/// The backdrop behind Home: deep navy with soft teal and violet light, like the icon.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Neon.navy, Neon.deepViolet, Neon.navy], startPoint: .top, endPoint: .bottom)
            glow(Neon.violet, opacity: 0.55, width: 520, height: 260, x: 140, y: -340)
            glow(Neon.teal, opacity: 0.35, width: 420, height: 200, x: 200, y: -380)
            glow(Neon.teal, opacity: 0.22, width: 480, height: 240, x: 190, y: 90)
            glow(Neon.violet, opacity: 0.35, width: 540, height: 260, x: -170, y: 430)
        }
        .ignoresSafeArea()
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
                    GlassScreenHeader(title: title, subtitle: subtitle, symbol: symbol)
                    content
                }
                .padding(.horizontal, Layout.screenPadding)
                .padding(.top, Space.s8)
                .padding(.bottom, Space.s24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background { AuroraBackground() }
            #if os(macOS)
            .toolbar(.hidden, for: .windowToolbar)
            #else
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }
}

struct GlassScreenHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String

    var body: some View {
        HStack(spacing: Space.s12) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Neon.teal)
                .frame(width: 52, height: 52)
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.md))

            VStack(alignment: .leading, spacing: Space.s4) {
                Text(title)
                    .font(TypeRole.display)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(TypeRole.footnote)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
        VStack(alignment: .leading, spacing: Space.s12) {
            if let title {
                Label {
                    Text(title)
                } icon: {
                    if let symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(Neon.teal)
                    }
                }
                .font(TypeRole.headline)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.lg))
    }
}

// MARK: - Platform cards

/// How each platform's Home card looks. Home only; the rest of the app uses the plain platform data.
/// Highlights use a non-breaking space before each bullet so a wrapped line never starts with one.
struct PlatformArt {
    let highlights: String
    let iconColor: Color
    let artSymbol: String
    let artColors: [Color]

    static func forPlatform(_ id: String) -> PlatformArt {
        switch id {
        case "instagram":
            return PlatformArt(highlights: "Friends\u{00A0}• Stories\u{00A0}• DMs", iconColor: Neon.teal,
                               artSymbol: "sun.horizon.fill", artColors: [Neon.magenta, Neon.orange])
        case "youtube":
            return PlatformArt(highlights: "Videos\u{00A0}• Channels\u{00A0}• Live", iconColor: Neon.red,
                               artSymbol: "mountain.2.fill", artColors: [Neon.violet, Neon.blue])
        case "youtube_music":
            return PlatformArt(highlights: "Music\u{00A0}• Playlists\u{00A0}• Radio", iconColor: Neon.teal,
                               artSymbol: "headphones", artColors: [Neon.violet, Neon.magenta])
        default:
            return PlatformArt(highlights: "", iconColor: Neon.teal,
                               artSymbol: "sparkles", artColors: [Neon.violet, Neon.blue])
        }
    }
}

/// A Liquid Glass card that opens a platform. Its artwork fades in from the trailing edge,
/// so the leading side, where the text sits, is plain glass over the background.
struct PlatformCard: View {
    let platform: Platform
    var isWide = false
    let action: () -> Void

    private var art: PlatformArt { .forPlatform(platform.id) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.lg, style: .continuous) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s8) {
                // The chevron sits up beside the icon so the subtitle below gets the card's full width.
                HStack(alignment: .top) {
                    Image(systemName: platform.symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(art.iconColor)
                        .shadow(color: art.iconColor.opacity(0.6), radius: 8)
                    Spacer(minLength: Space.s8)
                    Image(systemName: "chevron.right")
                        .font(TypeRole.footnote.weight(.bold))
                        .foregroundStyle(Neon.teal)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: Circle())
                }
                Spacer(minLength: Space.s12)
                Text(platform.name)
                    .font(TypeRole.title3)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                // Wraps to a second line on half-width cards rather than being cut off.
                Text(art.highlights.uppercased())
                    .font(TypeRole.caption)
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s16)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
            .background(alignment: .trailing) { artwork }
            .clipShape(shape)
            .contentShape(shape)
            .glassEffect(.regular.tint(Neon.violet.opacity(0.12)).interactive(), in: shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(platform.name)
        .accessibilityHint("Opens \(platform.name)")
    }

    private var artwork: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(colors: art.artColors.map { $0.opacity(0.75) },
                           startPoint: .topTrailing, endPoint: .bottomLeading)
            Image(systemName: art.artSymbol)
                .font(.system(size: isWide ? 110 : 84))
                .foregroundStyle(.white.opacity(0.14))
                .padding(.trailing, Space.s12)
        }
        .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
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
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pick.title)
                            .font(TypeRole.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(platformName)
                            .font(TypeRole.caption)
                            .foregroundStyle(.white.opacity(0.65))
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
        return Array(symbols[1...] + symbols[..<1])
    }

    var body: some View {
        let counts = insights.dailyCounts
        let highestCount = max(counts.max() ?? 0, 1)

        VStack(alignment: .leading, spacing: Space.s12) {
            Label {
                Text("Your Weekly Insights")
            } icon: {
                Image(systemName: "chart.bar.fill").foregroundStyle(Neon.teal)
            }
            .font(TypeRole.headline)
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)

            HStack(alignment: .bottom, spacing: Space.s16) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(insights.totalHidden, format: .number)
                        .font(TypeRole.display)
                        .foregroundStyle(Neon.teal)
                    Text("items filtered this week")
                        .font(TypeRole.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(counts.indices, id: \.self) { index in
                        VStack(spacing: Space.s4) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Neon.teal.opacity(counts[index] == 0 ? 0.18 : 0.85))
                                .frame(
                                    width: 18,
                                    height: max(4, 44 * CGFloat(counts[index]) / CGFloat(highestCount))
                                )
                            Text(days[index])
                                .font(TypeRole.caption)
                                .foregroundStyle(.white.opacity(0.6))
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
