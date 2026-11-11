import SwiftData
import SwiftUI

/// S07 and S08: a platform's own website with the switched-on filters applied.
/// S09: when the page is one reel a friend sent, the bar turns into "Back to chat".
struct PlatformScreen: View {
    let platform: Platform

    @Environment(RuleStore.self) private var ruleStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settings: [PlatformSetting]
    @Query private var accounts: [Account]
    @State private var model: WebModel?
    @State private var accountLabel: String?
    @State private var showQuickPost = false
    @State private var showAccounts = false

    private var toggles: [String: Bool] {
        settings.first { $0.platformID == platform.id }?.ruleToggles ?? [:]
    }

    var body: some View {
        VStack(spacing: 0) {
            WebTopBar(
                title: platform.name,
                accountLabel: accountLabel,
                showsBack: model?.isSingleItem ?? false,
                onClose: { dismiss() },
                onPost: { showQuickPost = true },
                onBack: { model?.goBack() },
                onAccount: { showAccounts = true },
                onReload: { model?.reload() }
            )
            ZStack {
                if let model {
                    WebViewContainer(model: model)
                    overlay(for: model)
                } else {
                    ProgressView().accessibilityLabel("Loading")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.color.bg)
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
            rules: ruleStore.enabledRules(for: platform.id, toggles: toggles)
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
