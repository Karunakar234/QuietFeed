// Design-system primitives. Built once, in isolation, before any screen.
// Every component reads Theme tokens only (no raw colours or sizes).
// Open DesignGallery in Xcode previews (light, dark, XXL text) as the design check.
import SwiftUI

// MARK: - Button

enum ButtonVariant { case primary, secondary, ghost, danger }
enum ButtonSize {
    case sm, md, lg
    var height: CGFloat { switch self { case .sm: 36; case .md: 44; case .lg: 52 } }
    var font: Font { self == .sm ? TypeRole.footnote.weight(.semibold) : TypeRole.headline }
}

struct AppButtonStyle: ButtonStyle {
    var variant: ButtonVariant = .primary
    var size: ButtonSize = .lg
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    private var palette: (bg: Color, fg: Color, stroke: Color?) {
        let c = Theme.color
        switch variant {
        case .primary: return (c.accent, c.onAccent, nil)
        case .secondary: return (c.surface, c.text, c.border)
        case .ghost: return (.clear, c.accent, nil)
        case .danger: return (c.danger, c.onAccent, nil)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let bg = palette.bg
        let fg = palette.fg
        let stroke = palette.stroke
        ZStack {
            configuration.label.opacity(isLoading ? 0 : 1)   // label stays in the tree for VoiceOver
            if isLoading { ProgressView().tint(fg) }
        }
        .font(size.font)
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity, minHeight: max(size.height, Layout.minTap))
        .padding(.horizontal, Space.s16)
        .background(bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            if let stroke { RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(stroke) }
        }
        .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
        .animation(.easeOut(duration: Motion.fast), value: configuration.isPressed)
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static func app(_ v: ButtonVariant = .primary, _ s: ButtonSize = .lg, loading: Bool = false) -> AppButtonStyle {
        AppButtonStyle(variant: v, size: s, isLoading: loading)
    }
}

// MARK: - Pro badge

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(TypeRole.caption.weight(.bold))
            .padding(.horizontal, Space.s8).padding(.vertical, Space.s4)
            .foregroundStyle(Theme.color.onAccentSoft)
            .background(Theme.color.accentSoft, in: Capsule())
            .accessibilityLabel("Pro feature")
    }
}

// MARK: - Platform tile (S02, S06)

enum TileState { case enabled, disabled, locked }

struct PlatformTile: View {
    let name: String
    let symbol: String          // generic SF Symbol, never a platform logo redrawn
    var subtitle: String? = nil
    var state: TileState = .enabled
    var isSelected = false      // onboarding picker mode
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s8) {
                HStack {
                    Image(systemName: symbol).font(.title2).foregroundStyle(Theme.color.accent)
                    Spacer()
                    if state == .locked { ProBadge() }
                    if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.color.accent) }
                }
                Spacer(minLength: Space.s12)
                Text(name).font(TypeRole.headline).foregroundStyle(Theme.color.text)
                if let subtitle {
                    Text(subtitle).font(TypeRole.footnote).foregroundStyle(Theme.color.textMuted)
                }
            }
            .padding(Space.s16)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(Theme.color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(isSelected ? Theme.color.accent : Theme.color.border, lineWidth: isSelected ? 2 : 1))
            .themeShadow(Shadow.card)
            .opacity(state == .disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(state == .locked ? "Requires Pro" : "")
    }
}

// MARK: - Toggle row (S12, S13, S16)

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var isLocked = false
    var onLockedTap: () -> Void = {}

    var body: some View {
        HStack(spacing: Space.s12) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: Space.s8) {
                    Text(title).font(TypeRole.body).foregroundStyle(Theme.color.text)
                    if isLocked { ProBadge() }
                }
                if let subtitle {
                    Text(subtitle).font(TypeRole.footnote).foregroundStyle(Theme.color.textMuted)
                }
            }
            Spacer()
            if isLocked {
                Button(action: onLockedTap) { Image(systemName: "lock.fill").foregroundStyle(Theme.color.textMuted) }
                    .frame(minWidth: Layout.minTap, minHeight: Layout.minTap)
                    .accessibilityLabel("Unlock with Pro")
            } else {
                Toggle("", isOn: $isOn).labelsHidden().tint(Theme.color.accent)
            }
        }
        .frame(minHeight: Layout.minTap)
        .accessibilityElement(children: isLocked ? .contain : .combine)
    }
}

// MARK: - Plan card (S05)

struct PlanCard: View {
    let title: String
    let price: String
    let detail: String
    var badge: String? = nil
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? Theme.color.accent : Theme.color.borderInput)
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack {
                        Text(title).font(TypeRole.headline)
                        if let badge {
                            Text(badge).font(TypeRole.caption.weight(.bold))
                                .padding(.horizontal, Space.s8).padding(.vertical, Space.s4)
                                .foregroundStyle(Theme.color.onAccent)
                                .background(Theme.color.accent, in: Capsule())
                        }
                    }
                    Text(detail).font(TypeRole.footnote).foregroundStyle(Theme.color.textMuted)
                }
                Spacer()
                Text(price).font(TypeRole.headline)
            }
            .foregroundStyle(Theme.color.text)
            .padding(Space.s16)
            .background(Theme.color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(isSelected ? Theme.color.accent : Theme.color.border, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Web container states (S07–S09)

enum WebState: Equatable {
    case loading(progress: Double)
    case loaded
    case offline
    case error(String)
    case filtersUpdating      // remote rules being applied
    case filterProblem        // engine detected a rule miss
}

struct WebStateOverlay: View {
    let state: WebState
    var retry: () -> Void = {}
    var report: () -> Void = {}

    var body: some View {
        switch state {
        case .loading(let p):
            VStack { ProgressView(value: p).tint(Theme.color.accent); Spacer() }
                .accessibilityLabel("Loading").accessibilityValue("\(Int(p * 100)) percent")
        case .loaded:
            EmptyView()
        case .offline:
            EmptyState(symbol: "wifi.slash", title: "You're offline",
                       message: "Reconnect and try again. Your filters stay on.",
                       actionTitle: "Try again", action: retry)
        case .error(let msg):
            EmptyState(symbol: "exclamationmark.triangle", title: "Page didn't load",
                       message: msg, actionTitle: "Reload", action: retry)
        case .filtersUpdating:
            VStack { Banner(kind: .info, text: "Updating filters…"); Spacer() }
        case .filterProblem:
            VStack {
                Banner(kind: .warning, text: "Something slipped through? Tell us.", actionTitle: "Report", action: report)
                Spacer()
            }
        }
    }
}

// MARK: - Web top bar (S07–S09)

struct WebTopBar: View {
    let title: String
    var accountLabel: String? = nil
    var showsBack = false
    var onClose: (() -> Void)? = nil
    var onPost: (() -> Void)? = nil
    var onMinimize: (() -> Void)? = nil
    var onBack: () -> Void = {}
    var onAccount: () -> Void = {}
    var onReload: () -> Void = {}

    var body: some View {
        HStack(spacing: Space.s8) {
            if showsBack {
                Button(action: onBack) { Image(systemName: "chevron.backward") }
                    .frame(width: Layout.minTap, height: Layout.minTap)
                    .accessibilityLabel("Back to chat")
            } else if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }
                    .frame(width: Layout.minTap, height: Layout.minTap)
                    .accessibilityLabel("Close")
            }
            Button(action: onAccount) {
                HStack(spacing: Space.s4) {
                    Text(title).font(TypeRole.headline)
                    if let accountLabel {
                        Text("· \(accountLabel)").font(TypeRole.footnote).foregroundStyle(Theme.color.textMuted)
                    }
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .accessibilityHint("Switch account")
            Spacer()
            if let onPost {
                Button("Post", action: onPost)
                    .font(TypeRole.footnote.weight(.semibold))
                    .padding(.horizontal, Space.s12)
                    .frame(minHeight: Layout.minTap)
                    .foregroundStyle(Theme.color.accent)
                    .accessibilityHint("Opens the real app for 10 minutes")
            }
            if let onMinimize {
                Button(action: onMinimize) { Image(systemName: "pip.enter") }
                    .frame(width: Layout.minTap, height: Layout.minTap)
                    .accessibilityLabel("Shrink to mini player")
            }
            Button(action: onReload) { Image(systemName: "arrow.clockwise") }
                .frame(width: Layout.minTap, height: Layout.minTap)
                .accessibilityLabel("Reload")
        }
        .foregroundStyle(Theme.color.text)
        .padding(.horizontal, Space.s8)
        .frame(height: Layout.webTopBar)
        .background(Theme.color.bg)
        .overlay(alignment: .bottom) { Theme.color.border.frame(height: 1) }
    }
}

// MARK: - Countdown (S11, Live Activity uses the same layout)

struct CountdownView: View {
    let endsAt: Date
    var label = "Quick Post"

    var body: some View {
        VStack(spacing: Space.s4) {
            Text(label).font(TypeRole.footnote).foregroundStyle(Theme.color.textMuted)
            Text(timerInterval: Date.now...max(endsAt, Date.now), countsDown: true)
                .font(TypeRole.stat).foregroundStyle(Theme.color.text)
                .contentTransition(.numericText(countsDown: true))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), time remaining")
    }
}

// MARK: - Stat card (S06, S14)

struct StatCard: View {
    let title: String
    let value: String?          // nil = no data yet
    var delta: String? = nil
    var deltaIsGood = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(title).font(TypeRole.footnote).foregroundStyle(Theme.color.textMuted)
            if let value {
                Text(value).font(TypeRole.stat).foregroundStyle(Theme.color.text)
                if let delta {
                    Text(delta).font(TypeRole.caption)
                        .foregroundStyle(deltaIsGood ? Theme.color.success : Theme.color.danger)
                }
            } else {
                Text("No data yet").font(TypeRole.body).foregroundStyle(Theme.color.textMuted)
            }
        }
        .padding(Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Banner / toast

enum BannerKind { case info, success, warning, error }

struct Banner: View {
    let kind: BannerKind
    let text: String
    var actionTitle: String? = nil
    var action: () -> Void = {}

    private var tint: Color {
        switch kind {
        case .info: Theme.color.accent
        case .success: Theme.color.success
        case .warning: Theme.color.warning
        case .error: Theme.color.danger
        }
    }
    private var symbol: String {
        switch kind {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(spacing: Space.s8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(TypeRole.footnote).foregroundStyle(Theme.color.text)
            Spacer(minLength: 0)
            if let actionTitle {
                Button(actionTitle, action: action).font(TypeRole.footnote.weight(.semibold)).tint(Theme.color.accent)
            }
        }
        .padding(Space.s12)
        .background(Theme.color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .themeShadow(Shadow.pop)
        .padding(.horizontal, Space.s16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: Space.s12) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(Theme.color.textMuted)
                .accessibilityHidden(true)
            Text(title).font(TypeRole.title3).foregroundStyle(Theme.color.text)
            Text(message).font(TypeRole.body).foregroundStyle(Theme.color.textMuted).multilineTextAlignment(.center)
            if let actionTitle {
                Button(actionTitle, action: action).buttonStyle(.app(.primary, .md)).frame(maxWidth: 240)
            }
        }
        .padding(Space.s24)
        .frame(maxWidth: Layout.maxReadableWidth)
    }
}

// MARK: - Gallery (the design-system check)

struct DesignGallery: View {
    @State private var toggleA = true
    @State private var toggleB = false
    @State private var plan = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s24) {
                section("Buttons") {
                    Button("Continue") {}.buttonStyle(.app())
                    Button("Restore purchases") {}.buttonStyle(.app(.secondary))
                    Button("Not now") {}.buttonStyle(.app(.ghost, .md))
                    Button("Log out") {}.buttonStyle(.app(.danger, .md))
                    Button("Purchasing") {}.buttonStyle(.app(loading: true))
                    Button("Disabled") {}.buttonStyle(.app()).disabled(true)
                }
                section("Platform tiles") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.s12) {
                        PlatformTile(name: "Instagram", symbol: "camera", subtitle: "Feed & DMs") {}
                        PlatformTile(name: "YouTube", symbol: "play.rectangle", subtitle: "No Shorts", isSelected: true) {}
                        PlatformTile(name: "Facebook", symbol: "person.2", state: .locked) {}
                        PlatformTile(name: "X", symbol: "text.bubble", state: .disabled) {}
                    }
                }
                section("Toggle rows") {
                    ToggleRow(title: "Hide Reels", subtitle: "Tab, feed and profile grids", isOn: $toggleA)
                    ToggleRow(title: "Hide suggested posts", isOn: $toggleB, isLocked: true)
                }
                section("Plans") {
                    PlanCard(title: "Yearly", price: "$—", detail: "Billed once a year", badge: "Best value", isSelected: plan == 1) { plan = 1 }
                    PlanCard(title: "Monthly", price: "$—", detail: "Cancel anytime", isSelected: plan == 0) { plan = 0 }
                }
                section("Stats & countdown") {
                    HStack { StatCard(title: "Time saved today", value: "1h 12m", delta: "▲ 18m vs. avg"); StatCard(title: "This week", value: nil) }
                    CountdownView(endsAt: .now.addingTimeInterval(600)).frame(maxWidth: .infinity)
                }
                section("Banners") {
                    Banner(kind: .info, text: "Updating filters…")
                    Banner(kind: .warning, text: "Something slipped through?", actionTitle: "Report")
                    Banner(kind: .success, text: "Pro unlocked")
                    Banner(kind: .error, text: "Purchase failed")
                }
                section("Web chrome & states") {
                    WebTopBar(title: "Instagram", accountLabel: "personal", showsBack: true)
                    EmptyState(symbol: "wifi.slash", title: "You're offline", message: "Reconnect and try again.", actionTitle: "Try again")
                }
            }
            .padding(Layout.screenPadding)
        }
        .background(Theme.color.bg)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            Text(title).font(TypeRole.title3).foregroundStyle(Theme.color.text)
            content()
        }
    }
}

#Preview("Light") { DesignGallery() }
#Preview("Dark") { DesignGallery().preferredColorScheme(.dark) }
#Preview("XXL text") { DesignGallery().dynamicTypeSize(.accessibility2) }
