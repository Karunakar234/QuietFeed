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

    private var toggles: [String: Bool] {
        settings.first { $0.platformID == platform.id }?.ruleToggles ?? [:]
    }

    var body: some View {
        GeometryReader { geo in
            let minimized = session.isMinimized
            VStack(spacing: 0) {
                if !minimized {
                    WebTopBar(
                        title: platform.name,
                        accountLabel: accountLabel,
                        showsBack: model?.isSingleItem ?? false,
                        onClose: { close() },
                        onPost: { showQuickPost = true },
                        onMinimize: { minimize() },
                        onBack: { model?.goBack() },
                        onAccount: { showAccounts = true },
                        onReload: { model?.reload() }
                    )
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
            }
            .frame(width: minimized ? MiniPlayer.size.width : geo.size.width,
                   height: minimized ? MiniPlayer.size.height : geo.size.height)
            .background(Theme.color.bg)
            .clipShape(RoundedRectangle(cornerRadius: minimized ? Radius.md : 0, style: .continuous))
            .shadow(color: minimized ? Shadow.pop.color : .clear, radius: Shadow.pop.radius, y: Shadow.pop.y)
            .position(minimized
                      ? miniCenter(in: geo.size, dragging: miniDrag)
                      : CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
            .gesture(miniDragGesture(in: geo.size), including: minimized ? .all : .subviews)
        }
        // Full screen covers the tabs edge to edge; the mini-player leaves them visible and usable.
        .background {
            if !session.isMinimized { Theme.color.bg.ignoresSafeArea() }
        }
        .task { start() }
        .onChange(of: toggles) { _, new in
            model?.updateRules(ruleStore.enabledRules(for: platform.id, toggles: new))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model?.continuePlaybackInBackground()
            }
        }
        .sheet(isPresented: $showQuickPost) { QuickPostSheet(platformName: platform.name) }
        .sheet(isPresented: $showAccounts) { AccountsScreen(platform: platform) }
    }

    // MARK: - Mini-player

    private func minimize() { withAnimation(Motion.spring) { session.minimize() } }
    private func expand() { withAnimation(Motion.spring) { session.expand() } }
    private func close() { withAnimation(Motion.spring) { session.close() } }

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
                miniButton("playpause.fill", label: "Play or pause") { model?.togglePlayback() }
                miniButton("xmark", label: "Close \(platform.name)") { close() }
            }
            .padding(Space.s4)
        }
    }

    private func miniButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(TypeRole.footnote.weight(.semibold))
                .frame(width: Layout.minTap, height: Layout.minTap)
                .background(.ultraThinMaterial, in: Circle())
        }
        .foregroundStyle(Theme.color.text)
        .accessibilityLabel(label)
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
                withAnimation(Motion.spring) {
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
        model = WebModel(
            platform: platform,
            dataStoreID: account.id,
            rules: ruleStore.enabledRules(for: platform.id, toggles: toggles),
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
