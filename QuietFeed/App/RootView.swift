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
    case home, blocking, stats, settings
}

struct MainTabs: View {
    @State private var selection: AppTab = .home

    var body: some View {
        TabContent(selection: selection)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AuroraTabBar(selection: $selection)
                    .padding(.horizontal, horizontalDockPadding)
                    .padding(.vertical, Space.s8)
                    #if os(macOS)
                    .padding(.bottom, Space.s8)
                    #endif
                    .frame(maxWidth: .infinity)
                    .background {
                        LinearGradient(
                            colors: [.clear, Neon.navy.opacity(0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    }
            }
    }

    private var horizontalDockPadding: CGFloat {
        #if os(macOS)
        Space.s24
        #else
        Space.s12
        #endif
    }
}

private struct TabContent: View {
    let selection: AppTab

    var body: some View {
        switch selection {
        case .home:
            HomeScreen()
        case .blocking:
            BlockingScreen()
        case .stats:
            StatsScreen()
        case .settings:
            SettingsScreen()
        }
    }
}

private struct AuroraTabBar: View {
    @Binding var selection: AppTab

    private let items: [(AppTab, String, String)] = [
        (.home, "house.fill", "Home"),
        (.blocking, "hand.raised.fill", "Blocking"),
        (.stats, "chart.bar.fill", "Stats"),
        (.settings, "gearshape.fill", "Settings")
    ]

    var body: some View {
        GlassEffectContainer(spacing: Space.s4) {
            HStack(spacing: Space.s4) {
                ForEach(items, id: \.0) { tab, symbol, title in
                    AuroraTabButton(
                        symbol: symbol,
                        title: title,
                        isSelected: selection == tab
                    ) {
                        withAnimation(Motion.gentle) {
                            selection = tab
                        }
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(.black.opacity(0.24), in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [Neon.teal.opacity(0.7), .white.opacity(0.14), Neon.violet.opacity(0.55)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Neon.teal.opacity(0.18), radius: 18, y: 6)
        .shadow(color: .black.opacity(0.38), radius: 24, y: 12)
        .frame(maxWidth: 620)
    }
}

private struct AuroraTabButton: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(height: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? Neon.teal : .white.opacity(0.78))
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, Space.s4)
            .contentShape(Capsule())
            .glassEffect(
                isSelected
                    ? .regular.tint(Neon.teal.opacity(0.28)).interactive()
                    : .regular.interactive(),
                in: .capsule
            )
            .shadow(color: isSelected ? Neon.teal.opacity(0.45) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
