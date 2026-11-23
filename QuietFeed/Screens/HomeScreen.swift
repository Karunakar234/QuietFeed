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
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
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

    /// The platform that was still open when QuietFeed last quit or was stopped by the system.
    /// Offered, not reopened automatically, so a page that crashed the app can't do it again.
    private var platformToResume: Platform? {
        guard session.platform == nil, let id = session.recoveryPlatformID,
              enabled.contains(where: { $0.id == id }) else { return nil }
        return ruleStore.platform(id: id)
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
                    if showFocusModeCard && focus.isEnabled {
                        FocusModeHero { showFocusControls = true }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    if search.isEmpty, let platform = platformToResume {
                        ResumeCard(
                            platform: platform,
                            resume: { open(platform) },
                            dismiss: { withAnimation(Motion.gentle) { session.discardRecovery() } }
                        )
                        .transition(.opacity)
                    }
                    if enabled.isEmpty {
                        emptyState
                    } else {
                        if !search.isEmpty { SearchExtras(search: search) }
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
            .navigationTitle("QuietFeed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isSearchPresented {
                        TextField("Search QuietFeed", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .focused($isSearchFocused)
                            .frame(minWidth: 180, maxWidth: 280)
                            .submitLabel(.search)
                            .accessibilityLabel("Search QuietFeed")
                    } else {
                        Text("QuietFeed")
                            .font(TypeRole.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSearchPresented {
                        Button("Cancel") {
                            search = ""
                            isSearchFocused = false
                            isSearchPresented = false
                        }
                    } else {
                        Button {
                            isSearchPresented = true
                            isSearchFocused = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("Search QuietFeed")
                    }
                }
            }
            .task(id: platformToPreload?.id) { await preload(platformToPreload) }
            .animation(Motion.gentle, value: showFocusModeCard)
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

    @ViewBuilder
    private var platformGrid: some View {
        if shownPlatforms.isEmpty {
            Text("No platforms match “\(search)”.")
                .font(TypeRole.body)
                .foregroundStyle(Theme.color.textMuted)
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
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Neon.glow)
            }
            .font(TypeRole.headline)
            .foregroundStyle(Theme.color.text)
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
                Image(systemName: "sparkles").foregroundStyle(Neon.glow)
            }
            .font(TypeRole.headline)
            .foregroundStyle(Theme.color.text)
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

/// "Pick up where you left off": shown after a relaunch when a platform was open at the time.
private struct ResumeCard: View {
    let platform: Platform
    let resume: () -> Void
    let dismiss: () -> Void

    var body: some View {
        GlassSectionCard("Pick up where you left off", symbol: "arrow.uturn.forward.circle") {
            Text("\(platform.name) was open when QuietFeed last closed.")
                .font(TypeRole.footnote)
                .foregroundStyle(Theme.color.textMuted)
            HStack(spacing: Space.s8) {
                Button("Resume \(platform.name)", action: resume)
                    .buttonStyle(.app(.primary, .md))
                Button("Not now", action: dismiss)
                    .buttonStyle(.app(.ghost, .md))
            }
        }
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
                            .foregroundStyle(Neon.glow)
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
