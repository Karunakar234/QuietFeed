import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RootView: View {
    @Environment(RuleStore.self) private var ruleStore
    @Environment(\.modelContext) private var context
    @Environment(WeeklyInsightsStore.self) private var insights
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppLock.self) private var appLock
    @Environment(IntentRouter.self) private var intentRouter
    @Environment(FocusSessionStore.self) private var focus
    @Query private var settings: [PlatformSetting]
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var session = PlayerSession()
    @State private var showFocusBlocked = false

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            if !session.isVideoFullscreen {
                HStack {
                    MacWindowControlBar(onToggleFullScreen: {
                        session.expand()
                    })
                    Spacer()
                }
                .padding(.horizontal, Space.s4)
                .frame(height: 28)
                .accessibilityElement(children: .contain)
            }
            #endif

            Group {
                if !ruleStore.isLoaded {
                    VStack(spacing: Space.s12) {
                        ProgressView()
                        Text("Preparing your quieter feed")
                            .font(TypeRole.footnote)
                            .foregroundStyle(Theme.color.textMuted)
                    }
                    .padding(Space.s24)
                    .glassEffect(.regular, in: .rect(cornerRadius: Radius.lg))
                    .background { AuroraBackground() }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Loading")
                } else if didOnboard {
                    MainTabs()
                        // The open platform sits above the tabs, full screen or as the mini-player.
                        // It lives here rather than in a cover so shrinking it keeps the same web view playing.
                        .overlay {
                            if let platform = session.platform {
                                PlatformScreen(platform: platform, startURL: session.startURL).id(session.openID)
                            }
                        }
                        .environment(session)
                } else {
                    OnboardingFlow { didOnboard = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.color.bg)
        .preferredColorScheme(preferredColorScheme)
        // With the lock on, the cover also hides the screen whenever the app isn't active,
        // so the app switcher's snapshot doesn't show the open feed.
        .overlay {
            if appLock.isLocked || (appLock.isEnabled && scenePhase != .active) {
                LockCover()
            }
        }
        .task {
            await ruleStore.load()
            seedSettings()
            publishLauncher()
            takeWidgetRequest()
            openRequestedPlatform()
            await appLock.promptIfNeeded()
        }
        .onChange(of: intentRouter.pendingPlatformID) { _, _ in openRequestedPlatform() }
        .onChange(of: didOnboard) { _, _ in openRequestedPlatform() }
        .onChange(of: launcherSignature) { _, _ in publishLauncher() }
        // quietfeed://open/<platform> from a widget; any other QuietFeed link just opens the app.
        .onOpenURL { url in
            if let id = LauncherSnapshot.platformID(from: url) { intentRouter.pendingPlatformID = id }
        }
        .alert("Focus session active", isPresented: $showFocusBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Platform opening is blocked inside QuietFeed until the focus session ends.")
        }
        .onChange(of: scenePhase) { _, phase in
            // Save this week's batched counts before the system may suspend the app.
            if phase != .active { insights.flush() }
            if phase == .background { appLock.lock() }
            if phase == .active {
                takeWidgetRequest()
                Task { await appLock.promptIfNeeded() }
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    /// Opens the platform an "Open Platform" shortcut asked for, once the app is past onboarding.
    private func openRequestedPlatform() {
        guard let id = intentRouter.pendingPlatformID, ruleStore.isLoaded, didOnboard else { return }
        intentRouter.pendingPlatformID = nil
        guard let platform = ruleStore.platform(id: id) else { return }
        // Widgets and links skip Home, so the Focus block is checked here as well.
        guard !(focus.isActive && focus.blocksPlatforms) else {
            showFocusBlocked = true
            return
        }
        settings.first { $0.platformID == id }?.lastOpenedAt = .now
        withAnimation(Motion.gentle) { session.open(platform) }
    }

    /// A widget icon tapped while QuietFeed wasn't running hands its platform over through the
    /// App Group (the widget's intent may run in the extension).
    private func takeWidgetRequest() {
        if let id = LauncherSnapshot.takePendingPlatformID() { intentRouter.pendingPlatformID = id }
    }

    /// Changes whenever anything the launcher widgets show changes.
    private var launcherSignature: [String] {
        settings.map {
            "\($0.platformID)|\($0.isEnabled)|\($0.isFavorite)|\($0.sortOrder)|\($0.lastOpenedAt?.timeIntervalSince1970 ?? 0)"
        }
    }

    private func publishLauncher() {
        LauncherSnapshot.publish(settings: settings, platforms: ruleStore.platforms)
    }

    /// Makes sure every platform has a settings row, so screens never meet a missing one.
    private func seedSettings() {
        let existing = Set(settings.map(\.platformID))
        for (index, platform) in ruleStore.platforms.enumerated() where !existing.contains(platform.id) {
            context.insert(PlatformSetting(platformID: platform.id, sortOrder: index))
        }
    }
}

/// Covers everything while QuietFeed is locked. Audio and Picture in Picture keep playing.
private struct LockCover: View {
    @Environment(AppLock.self) private var appLock

    var body: some View {
        VStack(spacing: Space.s16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Neon.glow)
                .accessibilityHidden(true)
            Text("QuietFeed is locked")
                .font(TypeRole.title)
                .foregroundStyle(Theme.color.text)
                .accessibilityAddTraits(.isHeader)
            if appLock.isLocked {
                Button("Unlock") { Task { await appLock.unlock() } }
                    .buttonStyle(.app(.primary, .md))
                    .disabled(appLock.isAuthenticating)
                if appLock.lastError == .unavailable {
                    Text("Set a device passcode in Settings to unlock QuietFeed.")
                        .font(TypeRole.footnote)
                        .foregroundStyle(Theme.color.textMuted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(Layout.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.color.bg.ignoresSafeArea())
        // Nothing behind the cover is reachable by touch or VoiceOver.
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isModal)
    }
}

#if os(macOS)
private struct MacWindowControlBar: View {
    let onToggleFullScreen: () -> Void

    var body: some View {
        HStack(spacing: Space.s8) {
            windowButton("xmark", label: "Close window", tint: .red) {
                activeWindow?.performClose(nil)
            }
            windowButton("minus", label: "Minimize window", tint: .yellow) {
                activeWindow?.miniaturize(nil)
            }
            windowButton("arrow.up.left.and.arrow.down.right", label: "Enter or exit full screen", tint: .green) {
                onToggleFullScreen()
                activeWindow?.toggleFullScreen(nil)
            }
        }
        .frame(width: 52, height: 28, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var activeWindow: NSWindow? {
        NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
    }

    private func windowButton(
        _ symbol: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(.black.opacity(0.72))
                .frame(width: 12, height: 12)
                .background(tint, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 12, height: 12)
        .accessibilityLabel(label)
    }
}
#endif

enum AppTab: Hashable {
    case home, filters, blocking, stats, settings
}

struct MainTabs: View {
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeScreen()
            }
            Tab("Filters", systemImage: "line.3.horizontal.decrease.circle", value: .filters) {
                FiltersScreen()
            }
            Tab("Blocking", systemImage: "hand.raised", value: .blocking) {
                BlockingScreen()
            }
            Tab("Stats", systemImage: "chart.bar", value: .stats) {
                StatsScreen()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsScreen()
            }
        }
        .tint(Theme.color.accent)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
