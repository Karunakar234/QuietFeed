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
    @Environment(PlayerSession.self) private var session
    @Environment(WeeklyInsightsStore.self) private var insights
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]
    @Query private var accounts: [Account]
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var confirmDelete = false
    @State private var confirmDeleteInsights = false
    @State private var isDeleting = false

    var body: some View {
        GlassScreen(
            title: "Settings",
            subtitle: "Choose your platforms and control the data stored on this device.",
            symbol: "gearshape.fill"
        ) {
            VStack(spacing: Space.s16) {
                SettingsPlatformsCard(settings: settings)
                SettingsDataCard(
                    deleteInsightsAction: {
                        confirmDeleteInsights = true
                    },
                    deleteAction: {
                        confirmDelete = true
                    }
                )
                SettingsAboutCard()
            }
        }
        .confirmationDialog(
            "Delete weekly insight data?",
            isPresented: $confirmDeleteInsights,
            titleVisibility: .visible
        ) {
            Button("Delete weekly insight data", role: .destructive) {
                insights.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset your count of filtered items for this week back to zero.")
        }
        .confirmationDialog(
            "Delete everything QuietFeed has stored on this device?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete my data", role: .destructive) {
                Task { await deleteEverything() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Puts QuietFeed back the way it was on first launch: signs out of every platform by deleting
    /// all website data, clears this week's insights, resets every platform and filter switch,
    /// and goes back to onboarding.
    private func deleteEverything() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        // An open or mini-player page keeps its website data in use, and WebKit won't delete data
        // that's in use (the old version failed silently here), so close it first and give
        // WebKit a moment to release it.
        session.close()
        try? await Task.sleep(for: .milliseconds(300))

        // Every account's data store, including any left behind without an account record.
        var stores = Set(accounts.map(\.id))
        stores.formUnion(await WKWebsiteDataStore.allDataStoreIdentifiers)
        var stillInUse: [UUID] = []
        for id in stores {
            do { try await WKWebsiteDataStore.remove(forIdentifier: id) } catch { stillInUse.append(id) }
        }
        if !stillInUse.isEmpty {
            try? await Task.sleep(for: .seconds(1))
            for id in stillInUse { try? await WKWebsiteDataStore.remove(forIdentifier: id) }
        }
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)

        for account in accounts { context.delete(account) }
        for setting in settings {
            setting.isEnabled = false
            setting.ruleToggles = [:]
        }
        try? context.save()
        insights.reset()
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
    let deleteInsightsAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        GlassSectionCard("Your data", symbol: "externaldrive.fill") {
            VStack(alignment: .leading, spacing: Space.s12) {
                Text("Resets the count of items filtered this week back to zero.")
                    .font(TypeRole.footnote)
                    .foregroundStyle(.white.opacity(0.65))

                Button("Delete weekly insight data", role: .destructive, action: deleteInsightsAction)
                    .buttonStyle(.app(.secondary, .md))

                Divider()
                    .overlay(.white.opacity(0.12))
                    .padding(.vertical, Space.s4)

                Text("Signs you out of every platform in QuietFeed, clears your weekly insights and resets every switch, as on first launch. Your accounts on those platforms themselves aren't touched.")
                    .font(TypeRole.footnote)
                    .foregroundStyle(.white.opacity(0.65))

                Button("Delete my data", role: .destructive, action: deleteAction)
                    .buttonStyle(.app(.danger, .md))
            }
        }
    }
}

private struct SettingsAboutCard: View {
    var body: some View {
        GlassSectionCard("About", symbol: "info.circle.fill") {
            Text("QuietFeed is independent and not affiliated with Instagram, Meta, YouTube, Google, Netflix, Amazon or Spotify.")
                .font(TypeRole.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
