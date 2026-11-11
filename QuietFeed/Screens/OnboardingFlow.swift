import SwiftData
import SwiftUI

/// S01 welcome and S02 pick platforms. Two screens, skippable, no paywall and no
/// permission prompt: blocking the real apps is opt-in later, from the Blocking tab.
struct OnboardingFlow: View {
    let onFinish: () -> Void
    @State private var step = 0

    var body: some View {
        Group {
            if step == 0 {
                WelcomeScreen(onContinue: { step = 1 })
            } else {
                PickPlatformsScreen(onFinish: onFinish)
            }
        }
        .frame(maxWidth: Layout.maxReadableWidth)
        .padding(Layout.screenPadding)
    }
}

private struct WelcomeScreen: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            Spacer()
            Text("Keep your people. Skip the pull.")
                .font(TypeRole.display)
                .foregroundStyle(Theme.color.text)
            Text("Instagram and YouTube, without Reels, Shorts or the feed of strangers.")
                .font(TypeRole.body)
                .foregroundStyle(Theme.color.textMuted)
            Spacer()
            Button("Get started", action: onContinue).buttonStyle(.app())
        }
    }
}

private struct PickPlatformsScreen: View {
    let onFinish: () -> Void
    @Environment(RuleStore.self) private var ruleStore
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]

    private var anySelected: Bool { settings.contains { $0.isEnabled } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            Text("Where do you want a quieter feed?")
                .font(TypeRole.title)
                .foregroundStyle(Theme.color.text)
            Text("You can change this any time.")
                .font(TypeRole.body)
                .foregroundStyle(Theme.color.textMuted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.s12)], spacing: Space.s12) {
                ForEach(ruleStore.platforms) { platform in
                    let setting = settings.first { $0.platformID == platform.id }
                    PlatformTile(name: platform.name, symbol: platform.symbol, subtitle: platform.tagline,
                                 isSelected: setting?.isEnabled ?? false) {
                        setting?.isEnabled.toggle()
                    }
                }
            }
            Spacer()
            Button("Continue", action: onFinish).buttonStyle(.app()).disabled(!anySelected)
            Button("Not now", action: onFinish).buttonStyle(.app(.ghost, .md))
        }
    }
}
