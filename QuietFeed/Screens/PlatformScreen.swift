import SwiftData
import SwiftUI

/// The mini-player's window. YouTube asks embedded players to stay at least 200×200 points.
private enum MiniPlayer {
    static let size = CGSize(width: 240, height: 216)
    static let margin: CGFloat = 12
    /// Keeps the bottom corners clear of the tab bar.
    static let tabBarClearance: CGFloat = 60
}

/// S07 and S08: a platform's own website with the switched-on filters applied.
/// S09: when the page is one reel a friend sent, the bar turns into "Back to chat".
/// The same view is the mini-player: shrinking only changes its frame, so the web view,
/// and whatever it's playing, carries on.
struct PlatformScreen: View {
    let platform: Platform
    /// A page to open instead of the platform's home, such as a recommended search.
    var startURL: URL? = nil

    @Environment(RuleStore.self) private var ruleStore
    @Environment(PlayerSession.self) private var session
    @Environment(WeeklyInsightsStore.self) private var insights
    @Environment(UsageStore.self) private var usage
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settings: [PlatformSetting]
    @Query private var accounts: [Account]
    @State private var model: WebModel?
    @State private var accountLabel: String?
    @State private var showQuickPost = false
    @State private var showAccounts = false
    @State private var miniCorner = MiniCorner()
    @State private var miniDrag: CGSize = .zero

    /// Which corner of the screen the mini-player rests in.
    private struct MiniCorner: Equatable {
        var isTop = false
        var isLeading = false
    }

    /// The platform switches enabled on the Filters screen.
    private var enabledKeys: Set<String> {
        Set(ruleStore.enabledRules(for: platform.id, toggles: toggles).map(\.key))
    }
    private var hidesHeader: Bool { enabledKeys.contains("hide_header") }
    private var hidesFooter: Bool { enabledKeys.contains("hide_footer") }

    /// Scrolling down with either switch on lets the page fill the screen edge to edge.
    /// The site's selected bar follows the scroll direction in FilterEngine.js.
    private var isBrowsingFullScreen: Bool {
        !session.isMinimized && (model?.isImmersive ?? false) && (hidesHeader || hidesFooter)
    }

    /// With its header hidden, a platform looks like its own app: the page runs edge to edge on
    /// black, and QuietFeed's Back and Close sit in the site's own top bar, where its logo was,
    /// instead of a strip of their own.
    private var usesSiteBarLayout: Bool { hidesHeader && SiteBarSlot.forPlatform(platform.id) != nil }

    /// True until the page has finished its first load (or after a reload starts).
    private var isPageLoading: Bool {
        guard let model else { return true }
        if case .loading = model.state { return true }
        return false
    }

    private var toggles: [String: Bool] {
        settings.first { $0.platformID == platform.id }?.ruleToggles ?? [:]
    }

    var body: some View {
        GeometryReader { geo in
            let minimized = session.isMinimized
            let videoFullscreen = model?.isVideoFullscreen ?? false
            // Hide Header controls QuietFeed's chrome immediately. The site's own bars still
            // follow their existing scroll behavior from FilterEngine.js.
            let barHidden = !minimized && (hidesHeader || videoFullscreen)
            let fullBleed = barHidden || isBrowsingFullScreen
            VStack(spacing: 0) {
                if !minimized && !barHidden {
                    WebTopBar(
                        title: platform.name,
                        accountLabel: accountLabel,
                        showsBack: (model?.isSingleItem ?? false) || (model?.canGoBack ?? false),
                        backReturnsToChat: model?.isSingleItem ?? false,
                        onClose: { close() },
                        onPost: { showQuickPost = true },
                        onMinimize: { minimize() },
                        onBack: { model?.goBack() },
                        onAccount: { showAccounts = true },
                        onReload: { model?.reload() }
                    )
                    .gesture(swipeDownToMinimize)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                // With QuietFeed's header hidden, Back and Close sit centred in a slim strip of their
                // own above the page, so they never cover the site's controls. Sites get them inside
                // their own bar instead, and the strip only if that bar still can't be found once the
                // page has loaded; while it loads they float over the blank page, so nothing jumps.
                if barHidden && !videoFullscreen
                    && (!usesSiteBarLayout || (model?.siteNavAnchor == .missing && !isPageLoading)) {
                    FloatingControls(
                        platformName: platform.name,
                        showsBack: (model?.isSingleItem ?? false) || (model?.canGoBack ?? false),
                        backReturnsToChat: model?.isSingleItem ?? false,
                        // Always there, dimmed when unavailable, so it never disappears or
                        // slides in under a tap.
                        keepsBackSlot: true,
                        onBack: { model?.goBack() },
                        onClose: { close() }
                    )
                    .frame(maxWidth: .infinity)
                    .gesture(swipeDownToMinimize)
                }
                ZStack {
                    if let model {
                        WebViewContainer(model: model)
                            .accessibilityHidden(minimized)
                        if !minimized { overlay(for: model) }
                    } else {
                        ProgressView().accessibilityLabel("Loading")
                    }
                    if minimized { miniControls }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Back and Close take the slot of the site's logo, which the page keeps free and
                // reports frame by frame, so they line up with the site's icons and slide away
                // with its bar rather than over the content.
                .overlay(alignment: .topLeading) {
                    if barHidden && !videoFullscreen && usesSiteBarLayout,
                       case .visible(let slot) = model?.siteNavAnchor {
                        FloatingControls(
                            platformName: platform.name,
                            showsBack: (model?.isSingleItem ?? false) || (model?.canGoBack ?? false),
                            backReturnsToChat: model?.isSingleItem ?? false,
                            keepsBackSlot: true,
                            onBack: { model?.goBack() },
                            onClose: { close() }
                        )
                        .frame(width: max(slot.width, SiteNavAnchor.slotWidth), height: slot.height, alignment: .leading)
                        // Some logos start at the screen edge (YouTube's); keep Back off it.
                        .offset(x: max(slot.minX, Space.s8), y: slot.minY)
                        .gesture(swipeDownToMinimize)
                    }
                }
                .overlay(alignment: .top) {
                    if barHidden && !videoFullscreen && usesSiteBarLayout && isPageLoading
                        && (model?.siteNavAnchor ?? .missing) == .missing {
                        FloatingControls(
                            platformName: platform.name,
                            showsBack: (model?.isSingleItem ?? false) || (model?.canGoBack ?? false),
                            backReturnsToChat: model?.isSingleItem ?? false,
                            keepsBackSlot: true,
                            onBack: { model?.goBack() },
                            onClose: { close() }
                        )
                        .gesture(swipeDownToMinimize)
                    }
                }
                // Full screen, the page sits in a rounded glass-edged frame over the neon backdrop;
                // while browsing (and in the mini-player) it goes edge to edge instead.
                .background(Theme.color.bg)
                .clipShape(RoundedRectangle(cornerRadius: minimized || fullBleed ? 0 : Radius.lg, style: .continuous))
                .overlay {
                    if !minimized && !fullBleed { glassEdge(cornerRadius: Radius.lg) }
                }
                .padding([.horizontal, .bottom], minimized || fullBleed ? 0 : Space.s8)
            }
            .animation(Motion.gentle, value: fullBleed)
            .frame(width: minimized ? MiniPlayer.size.width : geo.size.width,
                   height: minimized ? MiniPlayer.size.height : geo.size.height)
            .background(minimized ? Theme.color.bg : .clear)
            .clipShape(RoundedRectangle(cornerRadius: minimized ? Radius.md : 0, style: .continuous))
            .overlay {
                if minimized { glassEdge(cornerRadius: Radius.md) }
            }
            .shadow(color: minimized ? Shadow.pop.color : .clear, radius: Shadow.pop.radius, y: Shadow.pop.y)
            .position(minimized
                      ? miniCenter(in: geo.size, dragging: miniDrag)
                      : CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
            .gesture(miniDragGesture(in: geo.size), including: minimized ? .all : .none)
        }
        // While browsing, the page runs to the bottom edge behind the home indicator, as in Safari.
        // The top stays clear of the status bar so the time and battery stay readable.
        .ignoresSafeArea(.container, edges: isBrowsingFullScreen ? .bottom : [])
        // Full screen covers the tabs edge to edge; the mini-player leaves them visible and usable.
        .background {
            if session.isMinimized {
                EmptyView()
            } else if usesSiteBarLayout {
                Color.black.ignoresSafeArea()
            } else {
                AuroraBackground()
            }
        }
        .task {
            start()
            usage.begin(platformID: platform.id)
        }
        .onDisappear {
            usage.end()
            // A page kept for an instant reopen stays loaded; any other page is released.
            if let model, !session.isPreloaded(model) { model.shutdown() }
        }
        .onChange(of: toggles) { _, new in
            model?.updateRules(ruleStore.enabledRules(for: platform.id, toggles: new))
        }
        .onChange(of: model?.isVideoFullscreen ?? false) { _, active in
            session.setVideoFullscreen(active)
        }
        .onChange(of: scenePhase) { previous, phase in
            #if DEBUG
            print("[QF-PIP] scene \(previous) -> \(phase)")
            #endif
            // Leaving goes active → inactive → background. Note what's playing while still
            // inactive (nothing is paused yet), then resume only that once in the background.
            if previous == .active && phase == .inactive {
                model?.notePlaybackBeforeBackground()
                #if os(iOS)
                // Picture in Picture can only start while the app is still on screen.
                model?.enterPictureInPictureIfPlaying()
                #endif
            } else if phase == .background {
                usage.end()
                model?.continuePlaybackInBackground()
            } else if phase == .active {
                usage.begin(platformID: platform.id)
                // Also covers a glance at Control Center (inactive and straight back), which
                // would otherwise leave the video floating over QuietFeed itself.
                #if os(iOS)
                model?.exitPictureInPicture()
                #endif
            }
        }
        .sheet(isPresented: $showQuickPost) { QuickPostSheet(platformName: platform.name) }
        .sheet(isPresented: $showAccounts) { AccountsScreen(platform: platform) }
    }

    // MARK: - Mini-player

    private func minimize() { withAnimation(Motion.gentle) { session.minimize() } }
    private func expand() { withAnimation(Motion.gentle) { session.expand() } }
    private func close() {
        if let model {
            // A working page is paused and kept, so opening this platform again is instant.
            // A page showing an error is released, so the next open starts afresh.
            switch model.state {
            case .offline, .error:
                model.shutdown()
            default:
                model.park()
                session.preload(model)
            }
        }
        session.setVideoFullscreen(false)
        withAnimation(Motion.gentle) { session.close() }
    }

    /// Pulling the top bar down shrinks the page, the way a video app's player does.
    /// It's on the bar only, so it never competes with scrolling the page.
    private var swipeDownToMinimize: some Gesture {
        DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.height > 60 { minimize() }
        }
    }

    /// Covers the shrunken page: tap to expand, plus play/pause and close.
    private var miniControls: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { expand() }
                .accessibilityElement()
                .accessibilityLabel("\(platform.name) mini player")
                .accessibilityHint("Opens it full screen")
                .accessibilityAddTraits(.isButton)
            HStack(spacing: Space.s4) {
                // Music players get the song controls, as on the lock screen.
                if model?.hasTrackControls ?? false {
                    miniButton("backward.end.fill", label: "Previous song") { model?.previousTrack() }
                }
                miniButton("playpause.fill", label: "Play or pause") { model?.togglePlayback() }
                if model?.hasTrackControls ?? false {
                    miniButton("forward.end.fill", label: "Next song") { model?.nextTrack() }
                }
                miniButton("xmark", label: "Close \(platform.name)") { close() }
            }
            .padding(Space.s4)
            // A soft shade behind the buttons, so a bright part of the shrunken page (Spotify's
            // white "Open App" pill) can't wash them out.
            .background {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: MiniPlayer.size.width)
                    .allowsHitTesting(false)
            }
        }
    }

    private func miniButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(TypeRole.footnote.weight(.semibold))
                .frame(width: Layout.minTap, height: Layout.minTap)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.color.text)
        .accessibilityLabel(label)
    }

    /// The light rim Liquid Glass panels have, drawn around the page and the mini-player.
    private func glassEdge(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08), Neon.teal.opacity(0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }

    /// Where the mini-player's centre sits: its resting corner, moved by any drag in progress.
    private func miniCenter(in bounds: CGSize, corner: MiniCorner? = nil, dragging offset: CGSize = .zero) -> CGPoint {
        let corner = corner ?? miniCorner
        let halfWidth = MiniPlayer.size.width / 2
        let halfHeight = MiniPlayer.size.height / 2
        let x = corner.isLeading ? MiniPlayer.margin + halfWidth : bounds.width - MiniPlayer.margin - halfWidth
        let y = corner.isTop ? MiniPlayer.margin + halfHeight : bounds.height - MiniPlayer.tabBarClearance - halfHeight
        return CGPoint(x: x + offset.width, y: y + offset.height)
    }

    /// Drag the mini-player anywhere; when let go it settles in the nearest corner.
    private func miniDragGesture(in bounds: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { miniDrag = $0.translation }
            .onEnded { value in
                let landing = miniCenter(in: bounds, dragging: value.predictedEndTranslation)
                withAnimation(Motion.gentle) {
                    miniCorner = MiniCorner(isTop: landing.y < bounds.height / 2,
                                            isLeading: landing.x < bounds.width / 2)
                    miniDrag = .zero
                }
            }
    }

    // MARK: - Page states

    @ViewBuilder
    private func overlay(for model: WebModel) -> some View {
        switch model.state {
        case .offline, .error:
            WebStateOverlay(state: model.state, retry: { model.reload() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.color.bg)
        default:
            WebStateOverlay(state: model.state, retry: { model.reload() })
                .allowsHitTesting(false)
        }
    }

    private func start() {
        guard model == nil else { return }
        let account = activeAccount()
        accountLabel = account.label
        let rules = ruleStore.enabledRules(for: platform.id, toggles: toggles)
        // The page loaded in the background, if it's this one, so there's nothing to wait for.
        if let ready = session.takePreloaded(platformID: platform.id, startURL: startURL, dataStoreID: account.id) {
            ready.updateRules(rules)
            model = ready
            return
        }
        model = WebModel(
            platform: platform,
            dataStoreID: account.id,
            rules: rules,
            startURL: startURL,
            insights: insights
        )
    }

    /// The signed-in session for this platform; the first visit creates one.
    private func activeAccount() -> Account {
        if let existing = accounts.first(where: { $0.platformID == platform.id && $0.isActive }) {
            return existing
        }
        let created = Account(platformID: platform.id, label: "Main")
        context.insert(created)
        // Persist the identifier immediately so WebKit reuses this account’s cookie store
        // after the app relaunches. Credentials remain managed by the website.
        try? context.save()
        return created
    }
}

/// The controls left when QuietFeed's browser header is hidden: Back, when the page has
/// somewhere to go back to, and Close, side by side. Most platforms get them centred in a slim
/// strip above the page; YouTube Music gets them in its own top bar, where the logo was.
/// Swiping down on them shrinks the page to the mini player.
private struct FloatingControls: View {
    let platformName: String
    let showsBack: Bool
    let backReturnsToChat: Bool
    /// Keeps Back in place, dimmed, when there's nowhere to go back to, so the pair always fits
    /// the fixed slot YouTube Music's bar keeps for it.
    var keepsBackSlot = false
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: Space.s4) {
            HStack(spacing: 0) {
                if showsBack || keepsBackSlot {
                    button("chevron.backward", label: backReturnsToChat ? "Back to chat" : "Back",
                           isEnabled: showsBack, action: onBack)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                button("xmark", label: "Close \(platformName)", action: onClose)
            }
        }
        .padding(.vertical, Space.s4)
        .animation(Motion.gentle, value: showsBack)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    private func button(_ symbol: String, label: String, isEnabled: Bool = true,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(TypeRole.body.weight(.semibold))
                // Dim the glyph itself; opacity on the button doesn't reach inside the glass.
                .foregroundStyle(Theme.color.text.opacity(isEnabled ? 1 : 0.35))
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
                .frame(width: Layout.minTap, height: Layout.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

/// S11 placeholder. Quick Post needs Screen Time blocking, which isn't built yet.
struct QuickPostSheet: View {
    let platformName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Space.s16) {
            EmptyState(symbol: "square.and.pencil", title: "Posting",
                       message: "The real \(platformName) app isn't blocked, so you can post there as usual. A 10-minute Quick Post arrives together with blocking.")
            Button("OK") { dismiss() }.buttonStyle(.app(.primary, .md))
        }
        .padding(Layout.screenPadding)
        .presentationDetents([.medium])
    }
}
