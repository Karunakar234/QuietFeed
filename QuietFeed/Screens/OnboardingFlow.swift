import SwiftData
import SwiftUI

/// S01 welcome and S02 pick platforms. Two screens, skippable, no paywall and no
/// permission prompt: blocking the real apps is opt-in later, from the Blocking tab.
struct OnboardingFlow: View {
    let onFinish: () -> Void
    @State private var step = 0

    var body: some View {
        ZStack {
            if step == 0 {
                WelcomeScreen(onContinue: { step = 1 })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                PickPlatformsScreen(onFinish: onFinish)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .frame(maxWidth: Layout.maxReadableWidth)
        .padding(.horizontal, Layout.screenPadding)
        .padding(.vertical, Space.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AuroraBackground() }
        .animation(Motion.spring, value: step)
    }
}

private struct WelcomeScreen: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: Space.s16) {
            ScrollView {
                VStack {
                    Spacer(minLength: Space.s16)

                    VStack(alignment: .leading, spacing: Space.s20) {
                        Image(.brandMark)
                            .resizable()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                            .shadow(color: Neon.teal.opacity(0.4), radius: 18)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: Space.s8) {
                            Text("Keep your people. Skip the pull.")
                                .font(TypeRole.display)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Instagram and YouTube, without Reels, Shorts or the feed of strangers.")
                                .font(TypeRole.body)
                                .foregroundStyle(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(Space.s24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: Radius.lg))

                    Spacer(minLength: Space.s16)
                }
                .frame(minHeight: 0)
                .containerRelativeFrame(.vertical) { len, _ in len }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            Button("Continue", action: onContinue)
                .buttonStyle(.app())
        }
    }
}

private struct PickPlatformsScreen: View {
    let onFinish: () -> Void
    @Environment(RuleStore.self) private var ruleStore
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]

    private var anySelected: Bool { settings.contains { $0.isEnabled } }

    var body: some View {
        VStack(spacing: Space.s16) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s20) {
                    HStack(spacing: Space.s12) {
                        Image(systemName: "checklist")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Neon.teal)
                            .frame(width: 52, height: 52)
                            .glassEffect(.regular, in: .rect(cornerRadius: Radius.md))

                        VStack(alignment: .leading, spacing: Space.s4) {
                            Text("Choose your platforms")
                                .font(TypeRole.title)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("You can change this any time.")
                                .font(TypeRole.body)
                                .foregroundStyle(.white.opacity(0.68))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    GlassEffectContainer(spacing: Space.s8) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.s12)], spacing: Space.s12) {
                            ForEach(ruleStore.platforms) { platform in
                                let setting = settings.first { $0.platformID == platform.id }
                                PlatformTile(name: platform.name, symbol: platform.symbol, subtitle: platform.tagline,
                                             isSelected: setting?.isEnabled ?? false) {
                                    setting?.isEnabled.toggle()
                                }
                            }
                        }
                    }
                }
                .padding(.top, Space.s8)
                .padding(.bottom, Space.s16)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: Space.s12) {
                Button("Continue", action: onFinish)
                    .buttonStyle(.app())
                    .disabled(!anySelected)
                Button("Not now", action: onFinish)
                    .buttonStyle(.app(.ghost, .md))
            }
        }
    }
}
#Preview("Welcome") {
    OnboardingFlow {}
        .environment(RuleStore(provider: BundledRuleProvider()))
        .modelContainer(for: [PlatformSetting.self, Account.self], inMemory: true)
}

#Preview("Pick Platforms") {
    PickPlatformsScreen(onFinish: {})
        .frame(maxWidth: Layout.maxReadableWidth)
        .padding(.horizontal, Layout.screenPadding)
        .padding(.vertical, Space.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AuroraBackground() }
        .environment(RuleStore(provider: BundledRuleProvider()))
        .modelContainer(for: [PlatformSetting.self, Account.self], inMemory: true)
}

