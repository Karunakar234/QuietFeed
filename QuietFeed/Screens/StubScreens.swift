import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct BlockingScreen: View {
    @Environment(FocusSessionStore.self) private var focus
    @State private var notificationMessage: String?

    var body: some View {
        GlassScreen(
            title: "Blocking",
            subtitle: "Pause platform opening inside QuietFeed during a timed focus session.",
            symbol: "hand.raised.fill"
        ) {
            VStack(spacing: Space.s16) {
                FocusStatusCard()
                GlassSectionCard("Session controls", symbol: "timer") {
                    ToggleRow(
                        title: "Block QuietFeed platforms",
                        subtitle: "Stops platform cards from opening while a focus session is active.",
                        isOn: Binding(
                            get: { focus.blocksPlatforms },
                            set: { focus.blocksPlatforms = $0 }
                        )
                    )

                    HStack {
                        Button("25 minutes") { Task { await focus.start(minutes: 25) } }
                        Button("50 minutes") { Task { await focus.start(minutes: 50) } }
                    }
                    .buttonStyle(.app(.secondary, .md))

                    if focus.isActive {
                        Button("End focus session", role: .destructive) { focus.stop() }
                            .buttonStyle(.app(.danger, .md))
                    }
                }

                GlassSectionCard("Notifications", symbol: "bell.fill") {
                    ToggleRow(
                        title: "Completion alert",
                        subtitle: "Ask iOS to notify you when a session finishes.",
                        isOn: Binding(
                            get: { focus.completionNotifications },
                            set: { enabled in
                                Task {
                                    let accepted = await focus.setNotificationsEnabled(enabled)
                                    if enabled && !accepted {
                                        notificationMessage = "Notifications are disabled in system settings."
                                    }
                                }
                            }
                        )
                    )
                    if let notificationMessage {
                        Text(notificationMessage)
                            .font(TypeRole.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Text("This blocks only content opened inside QuietFeed. It does not block the providers' installed apps.")
                    .font(TypeRole.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }
}

struct StatsScreen: View {
    @Environment(WeeklyInsightsStore.self) private var insights
    @Environment(UsageStore.self) private var usage
    @Environment(RuleStore.self) private var ruleStore

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }

    private var csv: String {
        usage.exportCSV { ruleStore.platform(id: $0)?.name ?? $0 }
    }

    var body: some View {
        GlassScreen(
            title: "Stats",
            subtitle: "Activity measured while platforms are open inside QuietFeed.",
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

                GlassSectionCard("QuietFeed usage", symbol: "hourglass") {
                    Text(Duration.seconds(usage.duration(since: weekStart)), format: .time(pattern: .hourMinute))
                        .font(TypeRole.stat)
                        .foregroundStyle(Neon.teal)
                    Text("time in opened platforms this week")
                        .font(TypeRole.footnote)
                        .foregroundStyle(.white.opacity(0.65))

                    ForEach(ruleStore.platforms) { platform in
                        let duration = usage.duration(platformID: platform.id, since: weekStart)
                        if duration > 0 {
                            HStack {
                                Text(platform.name)
                                Spacer()
                                Text(Duration.seconds(duration), format: .time(pattern: .hourMinute))
                            }
                            .font(TypeRole.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }

                GlassSectionCard("Export", symbol: "square.and.arrow.up") {
                    ShareLink(item: csv, subject: Text("QuietFeed usage export")) {
                        Label("Export usage as CSV", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.app(.secondary, .md))
                }
            }
        }
        .task {
            insights.refresh()
        }
    }
}

private struct FocusStatusCard: View {
    @Environment(FocusSessionStore.self) private var focus

    var body: some View {
        GlassSectionCard("Focus status", symbol: focus.isActive ? "leaf.fill" : "pause.circle") {
            if focus.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(focus.remaining(at: context.date)), format: .time(pattern: .minuteSecond))
                        .font(TypeRole.stat)
                        .foregroundStyle(Neon.teal)
                        .accessibilityLabel("Focus time remaining")
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Text("Session continues correctly while the app is backgrounded because it uses its saved end time.")
                    .font(TypeRole.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                Text("No focus session is active")
                    .font(TypeRole.headline)
                    .foregroundStyle(.white)
            }
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
    @Environment(UsageStore.self) private var usage
    @Environment(FocusSessionStore.self) private var focus
    @Environment(OfflineAudioLibrary.self) private var offlineAudio
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]
    @Query private var accounts: [Account]
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var confirmDelete = false
    @State private var confirmDeleteInsights = false
    @State private var isDeleting = false
    @State private var showFilters = false
    @State private var showOfflineAudio = false

    var body: some View {
        GlassScreen(
            title: "Settings",
            subtitle: "Choose your platforms and control the data stored on this device.",
            symbol: "gearshape.fill"
        ) {
            VStack(spacing: Space.s16) {
                SettingsFiltersCard {
                    showFilters = true
                }
                SettingsOfflineAudioCard {
                    showOfflineAudio = true
                }
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
        .sheet(isPresented: $showFilters) {
            FiltersSettingsSheet()
        }
        .sheet(isPresented: $showOfflineAudio) {
            OfflineAudioScreen()
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
        usage.reset()
        focus.stop()
        offlineAudio.reset()
        didOnboard = false
    }
}

private struct SettingsOfflineAudioCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Neon.teal)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("Offline audio")
                        .font(TypeRole.headline)
                    Text("Import audio files you own and listen without a network connection.")
                        .font(TypeRole.footnote)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .accessibilityHidden(true)
            }
            .padding(Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your offline audio library")
    }
}

private struct OfflineAudioScreen: View {
    @Environment(OfflineAudioLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var importsFile = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("QuietFeed imports audio files you choose. It cannot download protected music or video from streaming services.")
                }

                Section("Library") {
                    if library.tracks.isEmpty {
                        Text("No offline audio imported")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.tracks) { track in
                        HStack {
                            Button {
                                library.togglePlayback(of: track)
                            } label: {
                                Label(
                                    track.title,
                                    systemImage: library.playingTrackID == track.id && library.isPlaying
                                        ? "pause.circle.fill" : "play.circle.fill"
                                )
                            }
                            Spacer()
                            Button("Delete", role: .destructive) { library.remove(track) }
                        }
                    }
                }

                if let error = library.lastError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Offline audio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Import") { importsFile = true }
                }
            }
            .fileImporter(isPresented: $importsFile, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result {
                    library.importAudio(from: url)
                }
            }
        }
    }
}

private struct SettingsFiltersCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Neon.teal)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular, in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("Filters")
                        .font(TypeRole.headline)
                        .foregroundStyle(.white)
                    Text("Choose what appears on Home and inside each platform.")
                        .font(TypeRole.footnote)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Space.s8)

                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityHidden(true)
            }
            .padding(Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Filters")
        .accessibilityHint("Opens filter settings")
    }
}

private struct FiltersSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FiltersScreen()
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .padding(Space.s16)
                .accessibilityLabel("Close Filters")
            }
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
