import SwiftData
import SwiftUI

/// S06: the launcher. A Liquid Glass card per platform that's switched on, calm picks that open
/// a real search, and the weekly insights card.
struct HomeScreen: View {
    /// Switches the app to the Filters tab (the button beside search).
    var showFilters: () -> Void = {}

    @Environment(RuleStore.self) private var ruleStore
    @Environment(PlayerSession.self) private var session
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]
    @State private var search = ""

    private var enabled: [Platform] {
        settings.filter(\.isEnabled).compactMap { ruleStore.platform(id: $0.platformID) }
    }

    private var shownPlatforms: [Platform] {
        guard !search.isEmpty else { return enabled }
        return enabled.filter { $0.name.localizedStandardContains(search) }
    }

    /// Picks for platforms that are switched on, narrowed by the search text.
    private var shownPicks: [Recommendation] {
        let enabledIDs = Set(enabled.map(\.id))
        return Recommendation.all.filter { pick in
            guard enabledIDs.contains(pick.platformID) else { return false }
            guard !search.isEmpty else { return true }
            let platformName = ruleStore.platform(id: pick.platformID)?.name ?? ""
            return pick.title.localizedStandardContains(search) || platformName.localizedStandardContains(search)
        }
    }

    /// Two cards to a row; an odd last card spans the row.
    private var platformRows: [[Platform]] {
        stride(from: 0, to: shownPlatforms.count, by: 2).map {
            Array(shownPlatforms[$0..<min($0 + 2, shownPlatforms.count)])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s24) {
                    header
                    searchRow
                    if enabled.isEmpty {
                        emptyState
                    } else {
                        platformGrid
                        if !shownPicks.isEmpty { recommendations }
                        InsightsCard()
                    }
                }
                .padding(.horizontal, Layout.screenPadding)
                .padding(.bottom, Space.s24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { AuroraBackground() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: Space.s12) {
            Image(.brandMark)
                .resizable()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .shadow(color: Neon.teal.opacity(0.35), radius: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("QuietFeed")
                    .font(TypeRole.display)
                    .foregroundStyle(.white)
                Text("Your calmer entertainment hub")
                    .textCase(.uppercase)
                    .font(TypeRole.caption)
                    .tracking(2)
                    .foregroundStyle(Neon.teal)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, Space.s8)
    }

    private var searchRow: some View {
        GlassEffectContainer(spacing: Space.s8) {
            HStack(spacing: Space.s12) {
                HStack(spacing: Space.s8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityHidden(true)
                    TextField("Search platforms and picks", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .foregroundStyle(.white)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(.white.opacity(0.6))
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, Space.s16)
                .frame(minHeight: 50)
                .glassEffect(.regular, in: .capsule)

                Button(action: showFilters) {
                    Image(systemName: "slider.horizontal.3")
                        .font(TypeRole.body.weight(.semibold))
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Filters")
            }
        }
    }

    @ViewBuilder
    private var platformGrid: some View {
        if shownPlatforms.isEmpty {
            Text("No platforms match “\(search)”.")
                .font(TypeRole.body)
                .foregroundStyle(.white.opacity(0.75))
        } else {
            GlassEffectContainer(spacing: Space.s8) {
                VStack(spacing: Space.s12) {
                    ForEach(platformRows, id: \.[0].id) { row in
                        HStack(spacing: Space.s12) {
                            ForEach(row) { platform in
                                PlatformCard(platform: platform, isWide: row.count == 1) { open(platform) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var recommendations: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            Label {
                Text("Recommended for a quieter feed")
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(Neon.teal)
            }
            .font(TypeRole.headline)
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: Space.s8) {
                    HStack(spacing: Space.s12) {
                        ForEach(shownPicks) { pick in
                            if let platform = ruleStore.platform(id: pick.platformID) {
                                RecommendationCard(pick: pick, platformName: platform.name) {
                                    open(platform, at: pick.url(for: platform))
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.s16) {
            EmptyState(symbol: "square.grid.2x2", title: "Nothing here yet",
                       message: "Pick a platform to begin. You can add more later.")
            VStack(spacing: Space.s8) {
                ForEach(settings) { setting in
                    if let platform = ruleStore.platform(id: setting.platformID) {
                        ToggleRow(title: platform.name, subtitle: platform.tagline, isOn: Binding(
                            get: { setting.isEnabled },
                            set: { setting.isEnabled = $0 }
                        ))
                    }
                }
            }
        }
        .padding(Space.s16)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.lg))
    }

    private func open(_ platform: Platform, at url: URL? = nil) {
        withAnimation(Motion.spring) { session.open(platform, at: url) }
    }
}
