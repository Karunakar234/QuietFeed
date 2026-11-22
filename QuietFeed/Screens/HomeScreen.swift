import SwiftData
import SwiftUI

/// S06: the launcher. A Liquid Glass card per platform that's switched on, calm picks that open
/// a real search, and the weekly insights card.
struct HomeScreen: View {
    @Environment(RuleStore.self) private var ruleStore
    @Environment(PlayerSession.self) private var session
    @Environment(WeeklyInsightsStore.self) private var insights
    @Environment(FocusSessionStore.self) private var focus
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]
    @Query private var accounts: [Account]
    @State private var search = ""
    @State private var showFocusControls = false
    @State private var showBlockedMessage = false
    @AppStorage("showFocusModeCard") private var showFocusModeCard = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The platform most likely opened next, the last one opened (else the first card), loaded
    /// in the background while nothing is open so it opens without a loading screen.
    private var platformToPreload: Platform? {
        guard session.platform == nil else { return nil }
        return recents.first ?? enabled.first
    }

    /// Switched-on platforms, favourites first, otherwise in the person's chosen order.
    private var enabled: [Platform] {
        settings
            .filter(\.isEnabled)
            .sorted { ($0.isFavorite ? 0 : 1, $0.sortOrder) < ($1.isFavorite ? 0 : 1, $1.sortOrder) }
            .compactMap { ruleStore.platform(id: $0.platformID) }
    }

    /// Up to four switched-on platforms, most recently opened first.
    private var recents: [Platform] {
        settings
            .filter { $0.isEnabled && $0.lastOpenedAt != nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(4)
            .compactMap { ruleStore.platform(id: $0.platformID) }
    }

    private func setting(for platform: Platform) -> PlatformSetting? {
        settings.first { $0.platformID == platform.id }
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

    /// Three compact cards to a row on iPhone; larger text sizes get fewer, wider cards.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 100), spacing: Space.s12)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s24) {
                    header
                    searchRow
                    if showFocusModeCard {
                        FocusModeHero { showFocusControls = true }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    if enabled.isEmpty {
                        emptyState
                    } else {
                        if search.isEmpty && !recents.isEmpty { recentRow }
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
            .task(id: platformToPreload?.id) { await preload(platformToPreload) }
            .animation(Motion.gentle, value: showFocusModeCard)
            #if os(macOS)
            .toolbar(.hidden, for: .windowToolbar)
            #else
            .quietFeedNavigationChrome()
            #endif
        }
        .sheet(isPresented: $showFocusControls) {
            FocusQuickStartSheet()
        }
        .alert("Focus session active", isPresented: $showBlockedMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Platform opening is blocked inside QuietFeed until the focus session ends.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: Space.s12) {
            Image("BrandMark")
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
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
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
                LazyVGrid(columns: gridColumns, spacing: Space.s12) {
                    ForEach(shownPlatforms) { platform in
                        let setting = setting(for: platform)
                        ServiceCard(
                            platform: platform,
                            isFavorite: setting?.isFavorite ?? false,
                            action: { open(platform) },
                            toggleFavorite: {
                                withAnimation(Motion.gentle) { setting?.isFavorite.toggle() }
                            }
                        )
                    }
                }
            }
        }
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Label {
                Text("Jump back in")
            } icon: {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Neon.teal)
            }
            .font(TypeRole.headline)
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: Space.s8) {
                    HStack(spacing: Space.s8) {
                        ForEach(recents) { platform in
                            RecentChip(platform: platform) { open(platform) }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
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

    /// Starts loading `platform`'s home in the background, in its signed-in account. Waits a
    /// moment first, so launch and closing a page stay smooth, and skips a first visit (no
    /// account yet; opening it creates one).
    private func preload(_ platform: Platform?) async {
        guard let platform, session.preloadedPlatformID != platform.id else { return }
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, session.platform == nil,
              let account = accounts.first(where: { $0.platformID == platform.id && $0.isActive }) else { return }
        let toggles = setting(for: platform)?.ruleToggles ?? [:]
        session.preload(WebModel(
            platform: platform,
            dataStoreID: account.id,
            rules: ruleStore.enabledRules(for: platform.id, toggles: toggles),
            insights: insights
        ))
    }

    private func open(_ platform: Platform, at url: URL? = nil) {
        guard !(focus.isActive && focus.blocksPlatforms) else {
            showBlockedMessage = true
            return
        }
        setting(for: platform)?.lastOpenedAt = .now
        withAnimation(Motion.gentle) { session.open(platform, at: url) }
    }
}

private struct FocusQuickStartSheet: View {
    @Environment(FocusSessionStore.self) private var focus
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.s20) {
                if focus.isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Duration.seconds(focus.remaining(at: context.date)), format: .time(pattern: .minuteSecond))
                            .font(TypeRole.stat)
                            .foregroundStyle(Neon.teal)
                            .accessibilityLabel("Focus time remaining")
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    Button("End session", role: .destructive) { focus.stop() }
                        .buttonStyle(.app(.danger, .md))
                } else {
                    Text("Start a focus session")
                        .font(TypeRole.title)
                    Button("25 minutes") {
                        Task {
                            await focus.start(minutes: 25)
                            dismiss()
                        }
                    }
                    .buttonStyle(.app(.primary, .lg))
                    Button("50 minutes") {
                        Task {
                            await focus.start(minutes: 50)
                            dismiss()
                        }
                    }
                    .buttonStyle(.app(.secondary, .md))
                }
            }
            .padding(Layout.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AuroraBackground() }
            .navigationTitle("Focus Mode")
        }
        .presentationDetents([.medium])
    }
}
