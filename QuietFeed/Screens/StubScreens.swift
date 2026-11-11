import SwiftData
import SwiftUI
import WebKit

struct BlockingScreen: View {
    var body: some View {
        GlassScreen(
            title: "Blocking",
            subtitle: "Keep distracting apps out of reach without losing important notifications.",
            symbol: "hand.raised.fill"
        ) {
            GlassSectionCard {
                VStack(spacing: Space.s16) {
                    Image(systemName: "hand.raised.slash.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Neon.teal)
                        .frame(width: 88, height: 88)
                        .glassEffect(.regular, in: .circle)
                        .accessibilityHidden(true)

                    Text("Blocking is off")
                        .font(TypeRole.title3)
                        .foregroundStyle(.white)

                    Text("QuietFeed doesn't block your real apps, so their notifications keep working. Sending them here instead will be an option you turn on.")
                        .font(TypeRole.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s16)
            }
        }
    }
}

struct StatsScreen: View {
    @Environment(WeeklyInsightsStore.self) private var insights

    var body: some View {
        GlassScreen(
            title: "Stats",
            subtitle: "A simple view of the distractions QuietFeed has removed.",
            symbol: "chart.bar.fill"
        ) {
            VStack(spacing: Space.s16) {
                GlassSectionCard("This week", symbol: "sparkles") {
                    Text(insights.totalHidden, format: .number)
                        .font(TypeRole.stat)
                        .foregroundStyle(Neon.teal)
                    Text("items filtered")
                        .font(TypeRole.body)
                        .foregroundStyle(.white.opacity(0.7))
                }

                GlassSectionCard("Screen Time", symbol: "hourglass") {
                    Text("Time in feeds avoided")
                        .font(TypeRole.body)
                        .foregroundStyle(.white)
                    Text("Screen Time access isn't connected yet.")
                        .font(TypeRole.footnote)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .task {
            insights.refresh()
        }
    }
}

struct AccountsScreen: View {
    let platform: Platform

    @Query private var accounts: [Account]
    @Environment(\.dismiss) private var dismiss

    private var platformAccounts: [Account] {
        accounts.filter { $0.platformID == platform.id }
    }

    var body: some View {
        GlassScreen(
            title: "Accounts",
            subtitle: "Manage the session QuietFeed uses for this platform.",
            symbol: "person.crop.circle"
        ) {
            GlassSectionCard {
                Label(platform.name, systemImage: platform.symbol)
                    .font(TypeRole.headline)
                    .foregroundStyle(.white)

                ForEach(platformAccounts) { account in
                    Label(
                        account.label,
                        systemImage: account.isActive ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(account.isActive ? Neon.teal : .white.opacity(0.7))
                    .padding(.vertical, Space.s8)
                }

                Divider().overlay(.white.opacity(0.12))

                HStack {
                    Text("Add another account")
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    ProBadge()
                }
                .padding(.vertical, Space.s8)

                Text("More than one account per platform isn't available yet.")
                    .font(TypeRole.footnote)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.app(.secondary, .md))
        }
    }
}

struct SettingsScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]
    @Query private var accounts: [Account]
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var confirmDelete = false

    var body: some View {
        GlassScreen(
            title: "Settings",
            subtitle: "Choose your platforms and control the data stored on this device.",
            symbol: "gearshape.fill"
        ) {
            VStack(spacing: Space.s16) {
                SettingsPlatformsCard(settings: settings)
                SettingsDataCard {
                    confirmDelete = true
                }
                SettingsAboutCard()
            }
        }
        .confirmationDialog(
            "Delete everything QuietFeed has stored on this phone?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete my data", role: .destructive) {
                Task { await deleteEverything() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteEverything() async {
        for account in accounts {
            try? await WKWebsiteDataStore.remove(forIdentifier: account.id)
            context.delete(account)
        }
        for setting in settings {
            setting.isEnabled = false
            setting.ruleToggles = [:]
        }
        didOnboard = false
    }
}

private struct SettingsPlatformsCard: View {
    let settings: [PlatformSetting]
    @Environment(RuleStore.self) private var ruleStore

    var body: some View {
        GlassSectionCard("Platforms", symbol: "square.grid.2x2.fill") {
            VStack(spacing: 0) {
                ForEach(settings) { setting in
                    if let platform = ruleStore.platform(id: setting.platformID) {
                        ToggleRow(
                            title: platform.name,
                            subtitle: platform.tagline,
                            isOn: Binding(
                                get: { setting.isEnabled },
                                set: { setting.isEnabled = $0 }
                            )
                        )
                        .padding(.vertical, Space.s8)

                        if setting.id != settings.last?.id {
                            Divider()
                                .overlay(.white.opacity(0.12))
                        }
                    }
                }
            }
        }
    }
}

private struct SettingsDataCard: View {
    let deleteAction: () -> Void

    var body: some View {
        GlassSectionCard("Your data", symbol: "externaldrive.fill") {
            Text("Signs you out everywhere in QuietFeed and resets your settings. Your Instagram and YouTube accounts aren't touched.")
                .font(TypeRole.footnote)
                .foregroundStyle(.white.opacity(0.65))

            Button("Delete my data", role: .destructive, action: deleteAction)
                .buttonStyle(.app(.danger, .md))
        }
    }
}

private struct SettingsAboutCard: View {
    var body: some View {
        GlassSectionCard("About", symbol: "info.circle.fill") {
            Text("QuietFeed is independent and not affiliated with Instagram, Meta, YouTube or Google.")
                .font(TypeRole.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
