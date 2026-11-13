import SwiftUI

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @State private var unavailablePlatform: TVPlatform?

    private let columns = [
        GridItem(.flexible(), spacing: 36),
        GridItem(.flexible(), spacing: 36),
        GridItem(.flexible(), spacing: 36)
    ]

    var body: some View {
        ZStack {
            TVAuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 42) {
                    header
                    Text("Choose a platform")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))

                    GlassEffectContainer(spacing: 24) {
                        LazyVGrid(columns: columns, spacing: 36) {
                            ForEach(TVPlatform.all) { platform in
                                platformButton(platform)
                            }
                        }
                    }

                    Text("Apple TV doesn't support embedded web views. QuietFeed opens the installed TV app when that platform provides one.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(maxWidth: 900, alignment: .leading)
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
                .frame(maxWidth: 1500)
                .frame(maxWidth: .infinity)
            }
        }
        .alert(
            unavailableTitle,
            isPresented: Binding(
                get: { unavailablePlatform != nil },
                set: { if !$0 { unavailablePlatform = nil } }
            ),
            presenting: unavailablePlatform
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { platform in
            Text(unavailableMessage(for: platform))
        }
    }

    private var unavailableTitle: LocalizedStringResource {
        #if targetEnvironment(simulator)
        "Requires a physical Apple TV"
        #else
        "App not available"
        #endif
    }

    private func unavailableMessage(for platform: TVPlatform) -> LocalizedStringResource {
        #if targetEnvironment(simulator)
        "The Apple TV simulator cannot install or open \(platform.name). Run QuietFeedTV on a paired physical Apple TV with \(platform.name) installed."
        #else
        "Install \(platform.name) from the Apple TV App Store, then try again."
        #endif
    }

    private var header: some View {
        HStack(spacing: 24) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.mint)
                .frame(width: 88, height: 88)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 6) {
                Text("QuietFeed")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("A calmer entertainment launcher for Apple TV")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func platformButton(_ platform: TVPlatform) -> some View {
        Button {
            openURL(platform.url) { accepted in
                if !accepted { unavailablePlatform = platform }
            }
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: platform.symbol)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(platform.tint)
                    Spacer()
                    Image(systemName: "arrow.up.forward.app.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 20)
                Text(platform.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(platform.detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .glassEffect(.regular.tint(platform.tint.opacity(0.16)).interactive(), in: .rect(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the installed \(platform.name) app")
    }
}

private struct TVPlatform: Identifiable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let tint: Color
    let url: URL

    static let all: [TVPlatform] = [
        TVPlatform(id: "youtube", name: "YouTube", detail: "Videos, channels, and live content", symbol: "play.rectangle.fill", tint: .red, url: URL(string: "https://www.youtube.com/tv")!),
        TVPlatform(id: "youtube_music", name: "YouTube Music", detail: "Music through the YouTube experience", symbol: "music.note.tv.fill", tint: .pink, url: URL(string: "https://music.youtube.com")!),
        TVPlatform(id: "netflix", name: "Netflix", detail: "Movies, series, and Netflix originals", symbol: "film.stack.fill", tint: .red, url: URL(string: "https://www.netflix.com")!),
        TVPlatform(id: "amazon_prime", name: "Prime Video", detail: "Movies and series in the Prime Video app", symbol: "play.tv.fill", tint: .cyan, url: URL(string: "https://www.primevideo.com")!),
        TVPlatform(id: "spotify", name: "Spotify", detail: "Music, podcasts, and playlists", symbol: "music.note.list", tint: .green, url: URL(string: "https://open.spotify.com")!)
    ]
}

private struct TVAuroraBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.10), Color(red: 0.08, green: 0.03, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.purple.opacity(0.35)).frame(width: 700).blur(radius: 140).offset(x: 500, y: -300)
            Circle().fill(.mint.opacity(0.22)).frame(width: 620).blur(radius: 130).offset(x: -560, y: 360)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    ContentView()
}
