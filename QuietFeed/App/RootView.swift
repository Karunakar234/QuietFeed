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
    @Query private var settings: [PlatformSetting]
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var session = PlayerSession()

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
                            .foregroundStyle(.white.opacity(0.72))
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
        .task {
            await ruleStore.load()
            seedSettings()
        }
        .onChange(of: scenePhase) { _, phase in
            // Save this week's batched counts before the system may suspend the app.
            if phase != .active { insights.flush() }
        }
    }

    /// Makes sure every platform has a settings row, so screens never meet a missing one.
    private func seedSettings() {
        let existing = Set(settings.map(\.platformID))
        for (index, platform) in ruleStore.platforms.enumerated() where !existing.contains(platform.id) {
            context.insert(PlatformSetting(platformID: platform.id, sortOrder: index))
        }
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
        #if os(macOS)
        ZStack(alignment: .bottom) {
            MacTabContent(selection: selection, showFilters: { selection = .filters })
            MacFloatingTabBar(selection: $selection)
                .padding(.bottom, Space.s16)
        }
        #else
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeScreen(showFilters: { selection = .filters })
            }
            Tab("Filters", systemImage: "slider.horizontal.3", value: .filters) { FiltersScreen() }
            Tab("Blocking", systemImage: "hand.raised", value: .blocking) { BlockingScreen() }
            Tab("Stats", systemImage: "chart.bar", value: .stats) { StatsScreen() }
            Tab("Settings", systemImage: "gearshape", value: .settings) { SettingsScreen() }
        }
        .tint(Neon.teal)
        #endif
    }
}

#if os(macOS)
private struct MacTabContent: View {
    let selection: AppTab
    let showFilters: () -> Void

    var body: some View {
        switch selection {
        case .home:
            HomeScreen(showFilters: showFilters)
        case .filters:
            FiltersScreen()
        case .blocking:
            BlockingScreen()
        case .stats:
            StatsScreen()
        case .settings:
            SettingsScreen()
        }
    }
}

private struct MacFloatingTabBar: View {
    @Binding var selection: AppTab
    @State private var isHovering = false

    private let items: [(AppTab, String, String)] = [
        (.home, "house.fill", "Home"),
        (.filters, "slider.horizontal.3", "Filters"),
        (.blocking, "hand.raised.fill", "Blocking"),
        (.stats, "chart.bar.fill", "Stats"),
        (.settings, "gearshape.fill", "Settings")
    ]

    var body: some View {
        GlassEffectContainer(spacing: Space.s4) {
            HStack(spacing: Space.s4) {
                ForEach(items, id: \.0) { tab, symbol, title in
                    Button {
                        withAnimation(Motion.gentle) { selection = tab }
                    } label: {
                        HStack(spacing: Space.s8) {
                            Image(systemName: symbol)
                                .frame(width: 20)
                            if isHovering || selection == tab {
                                Text(title)
                                    .font(TypeRole.footnote.weight(.semibold))
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                        .foregroundStyle(selection == tab ? Neon.teal : .white.opacity(0.78))
                        .padding(.horizontal, isHovering || selection == tab ? Space.s12 : Space.s8)
                        .frame(minHeight: Layout.minTap)
                        .contentShape(Capsule())
                        .glassEffect(
                            selection == tab
                                ? .regular.tint(Neon.teal.opacity(0.18)).interactive()
                                : .regular.interactive(),
                            in: .capsule
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
        }
        .padding(Space.s4)
        .onHover { hovering in
            withAnimation(Motion.gentle) { isHovering = hovering }
        }
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
    }
}
#endif
