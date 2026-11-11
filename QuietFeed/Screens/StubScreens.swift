import SwiftData
import SwiftUI
import WebKit

// Screens that exist in the shell but aren't built yet. Each says plainly what's missing.

/// S13 (plus S03, S04, S10): needs Apple's Family Controls entitlement before any of it runs.
struct BlockingScreen: View {
    var body: some View {
        NavigationStack {
            EmptyState(symbol: "hand.raised", title: "Blocking is off",
                       message: "QuietFeed doesn't block your real apps, so their notifications keep working. Sending them here instead will be an option you turn on.")
                .navigationTitle("Blocking")
        }
    }
}

/// S14: needs the Screen Time report extension.
struct StatsScreen: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Space.s16) {
                StatCard(title: "Time in feeds avoided today", value: nil)
                Spacer()
            }
            .padding(Layout.screenPadding)
            .navigationTitle("Stats")
        }
    }
}

/// S15: one account per platform for now.
struct AccountsScreen: View {
    let platform: Platform
    @Query private var accounts: [Account]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(accounts.filter { $0.platformID == platform.id }) { account in
                    Label(account.label, systemImage: account.isActive ? "checkmark.circle.fill" : "circle")
                }
                Section {
                    HStack {
                        Text("Add another account").foregroundStyle(Theme.color.textMuted)
                        Spacer()
                        ProBadge()
                    }
                } footer: {
                    Text("More than one account per platform isn't available yet.")
                }
            }
            .navigationTitle("\(platform.name) accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// S16, with the "undo everything" controls reviewers of other blockers asked for.
struct SettingsScreen: View {
    @Environment(RuleStore.self) private var ruleStore
    @Environment(\.modelContext) private var context
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]
    @Query private var accounts: [Account]
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section("Platforms") {
                    ForEach(settings) { setting in
                        if let platform = ruleStore.platform(id: setting.platformID) {
                            ToggleRow(title: platform.name, subtitle: platform.tagline, isOn: Binding(
                                get: { setting.isEnabled },
                                set: { setting.isEnabled = $0 }
                            ))
                        }
                    }
                }
                Section {
                    Button("Delete my data", role: .destructive) { confirmDelete = true }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Signs you out everywhere in QuietFeed and resets your settings. Your Instagram and YouTube accounts aren't touched.")
                }
                Section("About") {
                    Text("QuietFeed is independent and not affiliated with Instagram, Meta, YouTube or Google.")
                        .font(TypeRole.footnote)
                        .foregroundStyle(Theme.color.textMuted)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete everything QuietFeed has stored on this phone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete my data", role: .destructive) { Task { await deleteEverything() } }
                Button("Cancel", role: .cancel) {}
            }
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
