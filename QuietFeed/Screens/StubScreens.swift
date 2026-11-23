import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import Charts

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
                        Button("15 min") { Task { await focus.start(minutes: 15) } }
                        Button("25 min") { Task { await focus.start(minutes: 25) } }
                        Button("50 min") { Task { await focus.start(minutes: 50) } }
                    }
                    .buttonStyle(.app(.secondary, .md))

                    if focus.isActive {
                        Button("Pause session", systemImage: "pause.fill") { focus.pause() }
                            .buttonStyle(.app(.secondary, .md))
                        Button("End focus session", role: .destructive) { focus.stop() }
                            .buttonStyle(.app(.danger, .md))
                    } else if focus.isPaused {
                        Button("Resume session", systemImage: "play.fill") {
                            Task { await focus.resume() }
                        }
                        .buttonStyle(.app(.primary, .md))
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
                            .foregroundStyle(Theme.color.textMuted)
                    }
                }

                Text("This blocks only content opened inside QuietFeed. It does not block the providers' installed apps.")
                    .font(TypeRole.footnote)
                    .foregroundStyle(Theme.color.textMuted)
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
                        .foregroundStyle(Neon.glow)
                    Text("items filtered")
                        .font(TypeRole.body)
                        .foregroundStyle(Theme.color.textMuted)
                }

                GlassSectionCard("QuietFeed usage", symbol: "hourglass") {
                    let totalUsage = usage.duration(since: weekStart)
                    Text(Duration.seconds(totalUsage), format: .time(pattern: .hourMinute))
                        .font(TypeRole.stat)
                        .foregroundStyle(Neon.glow)
                    Text("time in opened platforms this week")
                        .font(TypeRole.footnote)
                        .foregroundStyle(Theme.color.textMuted)

                    if totalUsage == 0 && usage.records.isEmpty {
                        Text("No platform usage recorded yet this week.")
                            .font(TypeRole.footnote)
                            .foregroundStyle(Theme.color.textMuted)
                            .padding(.top, Space.s4)
                    }

                    Chart {
                        ForEach(ruleStore.platforms) { platform in
                            let duration = usage.duration(platformID: platform.id, since: weekStart)
                            if duration > 0 {
                                BarMark(
                                    x: .value("Platform", platform.name),
                                    y: .value("Minutes", duration / 60)
                                )
                                .foregroundStyle(by: .value("Platform", platform.name))
                            }
                        }
                    }
                    .frame(minHeight: 180)
                    .chartYAxisLabel("Minutes")
                    .accessibilityLabel("Platform usage this week")

                    ForEach(ruleStore.platforms) { platform in
                        let duration = usage.duration(platformID: platform.id, since: weekStart)
                        if duration > 0 {
                            HStack {
                                Text(platform.name)
                                Spacer()
                                Text(Duration.seconds(duration), format: .time(pattern: .hourMinute))
                            }
                            .font(TypeRole.footnote)
                            .foregroundStyle(Theme.color.textMuted)
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
                        .foregroundStyle(Neon.glow)
                        .accessibilityLabel("Focus time remaining")
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Text("Session continues correctly while the app is backgrounded because it uses its saved end time.")
                    .font(TypeRole.footnote)
                    .foregroundStyle(Theme.color.textMuted)
            } else if focus.isPaused {
                Text(Duration.seconds(focus.remaining()), format: .time(pattern: .minuteSecond))
                    .font(TypeRole.stat)
                    .foregroundStyle(Neon.glow)
                Text("Session paused")
                    .font(TypeRole.footnote)
                    .foregroundStyle(Theme.color.textMuted)
            } else {
                Text("No focus session is active")
                    .font(TypeRole.headline)
                    .foregroundStyle(.primary)
            }
        }
    }
}

struct AccountsScreen: View {
    let platform: Platform

    @Query private var accounts: [Account]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(PlayerSession.self) private var session
    @Environment(RuleStore.self) private var ruleStore
    @State private var confirmSignOut = false

    private var platformAccounts: [Account] {
        accounts.filter { $0.platformID == platform.id }
    }

    private var capabilities: PlatformCapabilities {
        PlatformCapabilities(platform: platform, filterCount: ruleStore.toggles(for: platform.id).count)
    }

    /// Signs out of this platform only: its page is closed, its website data (cookies, storage)
    /// deleted, and its account record removed. The next open starts a fresh, signed-out session.
    private func signOut() async {
        // Captured first: closing the page dismisses this sheet, and its queries with it.
        let signedIn = platformAccounts
        let ids = Set(signedIn.map(\.id))
        let context = context
        if session.platform?.id == platform.id { session.close() }
        session.discardPreloaded(platformID: platform.id)
        dismiss()
        // Give WebKit a moment to release the closed page's data store.
        try? await Task.sleep(for: .milliseconds(300))
        await WebsiteDataCleaner.remove(ids)
        for account in signedIn { context.delete(account) }
        try? context.save()
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
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(platformAccounts) { account in
                    Label(
                        account.label,
                        systemImage: account.isActive ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(account.isActive ? Neon.glow : Theme.color.textMuted)
                    .padding(.vertical, Space.s8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(account.label), \(account.isActive ? "Active" : "Inactive")")
                }

                Divider()

                HStack {
                    Text("Add another account")
                        .foregroundStyle(Theme.color.textMuted)
                    Spacer()
                    ProBadge()
                }
                .padding(.vertical, Space.s8)

                Text("More than one account per platform isn't available yet.")
                    .font(TypeRole.footnote)
                    .foregroundStyle(Theme.color.textMuted)

                if !platformAccounts.isEmpty {
                    Button("Sign out of \(platform.name)", role: .destructive) { confirmSignOut = true }
                        .buttonStyle(.app(.danger, .md))
                }
            }

            GlassSectionCard("What works here", symbol: "checklist") {
                ForEach(capabilities.features) { feature in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                        Image(systemName: feature.availability.symbol)
                            .foregroundStyle(feature.availability == .unavailable ? Theme.color.textMuted : Neon.glow)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(TypeRole.body)
                            if let note = feature.note {
                                Text(note)
                                    .font(TypeRole.footnote)
                                    .foregroundStyle(Theme.color.textMuted)
                            }
                        }
                        Spacer(minLength: Space.s8)
                        Text(feature.availability.label)
                            .font(TypeRole.footnote)
                            .foregroundStyle(Theme.color.textMuted)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, Space.s4)
                    .accessibilityElement(children: .combine)
                }
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.app(.secondary, .md))
        }
        .confirmationDialog(
            "Sign out of \(platform.name)?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) { Task { await signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This closes \(platform.name) and deletes its cookies and website data from QuietFeed. Your \(platform.name) account itself isn't touched.")
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
    @Environment(AppLock.self) private var appLock
    @Query(sort: \PlatformSetting.sortOrder) private var settings: [PlatformSetting]
    @Query private var accounts: [Account]
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var isDeleting = false
    @State private var showFilters = false
    @State private var showOfflineAudio = false
    @State private var showPlatforms = false
    @State private var showData = false

    var body: some View {
        NavigationStack {
            Form {
                ThemedSection("Appearance") {
                    Toggle(isOn: lightModeBinding) {
                        Label {
                            VStack(alignment: .leading, spacing: Space.s4) {
                                Text("Light Mode")
                                Text(appearanceMode == "light"
                                     ? "Always use a light appearance"
                                     : "Following System Appearance")
                                    .font(TypeRole.footnote)
                                    .foregroundStyle(Theme.color.textMuted)
                            }
                        } icon: {
                            Image(systemName: appearanceMode == "light" ? "sun.max.fill" : "circle.lefthalf.filled")
                                .foregroundStyle(Theme.color.accent)
                        }
                    }
                }

                ThemedSection("Content") {
                    Button {
                        showFilters = true
                    } label: {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }

                    Button {
                        showPlatforms = true
                    } label: {
                        Label("Platforms", systemImage: "square.grid.2x2")
                    }
                }

                ThemedSection("Focus") {
                    Toggle(
                        "Enable Focus Mode",
                        isOn: Binding(
                            get: { focus.isEnabled },
                            set: { focus.setEnabled($0) }
                        )
                    )
                }

                ThemedSection("Notifications") {
                    Toggle(
                        "Focus completion",
                        isOn: Binding(
                            get: { focus.completionNotifications },
                            set: { enabled in
                                Task { _ = await focus.setNotificationsEnabled(enabled) }
                            }
                        )
                    )
                }

                ThemedSection("Media") {
                    Button {
                        showOfflineAudio = true
                    } label: {
                        Label("Offline Audio", systemImage: "arrow.down.circle")
                    }
                }

                ThemedSection(
                    "Privacy & Data",
                    footer: "Locks QuietFeed when it goes to the background and hides it in the app switcher. Audio keeps playing."
                ) {
                    Toggle(
                        "Require Face ID or Passcode",
                        isOn: Binding(
                            get: { appLock.isEnabled },
                            set: { enabled in Task { await appLock.setEnabled(enabled) } }
                        )
                    )
                    .disabled(appLock.isAuthenticating)
                    if appLock.lastError == .unavailable {
                        Text("Set a device passcode to use the lock.")
                            .font(.footnote)
                            .foregroundStyle(Theme.color.textMuted)
                    }
                }

                Section {
                    Button {
                        showData = true
                    } label: {
                        Label("Your Data", systemImage: "externaldrive")
                    }
                }

                ThemedSection("Web Browser") {
                    LabeledContent("Website sessions", value: "Stored on this device")
                    Text("QuietFeed uses each provider's supported website and does not bypass authentication, advertising, or playback restrictions.")
                        .font(.footnote)
                        .foregroundStyle(Theme.color.textMuted)
                }

                ThemedSection("Accessibility") {
                    LabeledContent("Reduce Motion", value: reduceMotion ? "On" : "Off")
                    LabeledContent("Increase Contrast", value: colorSchemeContrast == .increased ? "On" : "Off")
                    Text("These settings follow your device's Accessibility preferences.")
                        .font(.footnote)
                        .foregroundStyle(Theme.color.textMuted)
                }

                ThemedSection("About") {
                    LabeledContent(
                        "Version",
                        value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
                    )
                    Text("QuietFeed is independent and is not affiliated with the supported entertainment services.")
                        .font(.footnote)
                        .foregroundStyle(Theme.color.textMuted)
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showFilters) {
            FiltersSettingsSheet()
        }
        .sheet(isPresented: $showOfflineAudio) {
            OfflineAudioScreen()
        }
        .sheet(isPresented: $showPlatforms) {
            PlatformsSettingsSheet(settings: settings)
        }
        .sheet(isPresented: $showData) {
            DataSettingsSheet(
                deleteInsightsAction: { insights.reset() },
                deleteAction: { Task { await deleteEverything() } }
            )
        }
    }

    private var lightModeBinding: Binding<Bool> {
        Binding(
            get: { appearanceMode == "light" },
            set: { appearanceMode = $0 ? "light" : "system" }
        )
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
        await WebsiteDataCleaner.remove(stores)
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
        appLock.reset()
        didOnboard = false
    }
}

private struct PlatformsSettingsSheet: View {
    let settings: [PlatformSetting]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassScreen(
            title: "Platforms",
            subtitle: "Choose the apps shown on Home.",
            symbol: "square.grid.2x2.fill"
        ) {
            SettingsPlatformsCard(settings: settings)
            Button("Done") { dismiss() }
                .buttonStyle(.app(.primary, .md))
        }
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

                ThemedSection("Library") {
                    if library.tracks.isEmpty {
                        Text("No offline audio imported")
                            .foregroundStyle(Theme.color.textMuted)
                    }
                    ForEach(library.tracks) { track in
                        HStack {
                            let isCurrent = library.playingTrackID == track.id && library.isPlaying
                            Button {
                                library.togglePlayback(of: track)
                            } label: {
                                Label(
                                    track.title,
                                    systemImage: isCurrent ? "pause.circle.fill" : "play.circle.fill"
                                )
                            }
                            .accessibilityLabel("\(isCurrent ? "Pause" : "Play") \(track.title)")
                            Spacer()
                            Button("Delete", role: .destructive) { library.remove(track) }
                                .accessibilityLabel("Delete \(track.title)")
                        }
                    }
                }

                if let error = library.lastError {
                    Section { Text(error).foregroundStyle(Theme.color.danger) }
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
                        .foregroundStyle(.primary)
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

    private var orderedSettings: [PlatformSetting] {
        settings.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        GlassSectionCard("Platforms", symbol: "square.grid.2x2.fill") {
            VStack(spacing: 0) {
                ForEach(orderedSettings) { setting in
                    if let platform = ruleStore.platform(id: setting.platformID) {
                        HStack(spacing: Space.s12) {
                            VStack(alignment: .leading, spacing: Space.s4) {
                                Text(platform.name)
                                    .font(TypeRole.body)
                                    .foregroundStyle(Theme.color.text)
                                if let tagline = platform.tagline {
                                    Text(tagline)
                                        .font(TypeRole.footnote)
                                        .foregroundStyle(Theme.color.textMuted)
                                }
                            }
                            Spacer()
                            Menu {
                                Button("Move earlier", systemImage: "arrow.up") { move(setting, by: -1) }
                                    .disabled(isFirst(setting))
                                Button("Move later", systemImage: "arrow.down") { move(setting, by: 1) }
                                    .disabled(isLast(setting))
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .frame(width: Layout.minTap, height: Layout.minTap)
                            }
                            .accessibilityLabel("Reorder \(platform.name)")
                            Toggle("Show \(platform.name) on Home", isOn: Binding(
                                get: { setting.isEnabled },
                                set: { setting.isEnabled = $0 }
                            ))
                            .labelsHidden()
                            .tint(Theme.color.accent)
                        }
                        .frame(minHeight: Layout.minTap)
                        .padding(.vertical, Space.s8)

                        if setting.id != orderedSettings.last?.id {
                            Divider()
                                .foregroundStyle(Theme.color.border)
                        }
                    }
                }
            }
        }
    }

    private func isFirst(_ setting: PlatformSetting) -> Bool { orderedSettings.first?.id == setting.id }
    private func isLast(_ setting: PlatformSetting) -> Bool { orderedSettings.last?.id == setting.id }

    private func move(_ setting: PlatformSetting, by offset: Int) {
        let ordered = orderedSettings
        guard let source = ordered.firstIndex(where: { $0.id == setting.id }) else { return }
        let destination = source + offset
        guard ordered.indices.contains(destination) else { return }
        let other = ordered[destination]
        (setting.sortOrder, other.sortOrder) = (other.sortOrder, setting.sortOrder)
    }
}

private struct DataSettingsSheet: View {
    let deleteInsightsAction: () -> Void
    let deleteAction: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteInsights = false
    @State private var confirmDelete = false

    var body: some View {
        GlassScreen(
            title: "Your data",
            subtitle: "Review and manage data stored by QuietFeed on this device.",
            symbol: "externaldrive.fill"
        ) {
            SettingsDataActionsCard(
                deleteInsightsAction: { confirmDeleteInsights = true },
                deleteAction: { confirmDelete = true }
            )

            Button("Done") { dismiss() }
                .buttonStyle(.app(.primary, .md))
        }
        .confirmationDialog(
            "Delete weekly insight data?",
            isPresented: $confirmDeleteInsights,
            titleVisibility: .visible
        ) {
            Button("Delete weekly insight data", role: .destructive, action: deleteInsightsAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset your count of filtered items for this week back to zero.")
        }
        .confirmationDialog(
            "Delete everything QuietFeed has stored on this device?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete my data", role: .destructive, action: deleteAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This signs you out of platforms in QuietFeed and resets app data. Your accounts with those services are not deleted.")
        }
    }
}

private struct SettingsDataActionsCard: View {
    let deleteInsightsAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        GlassSectionCard("Data controls", symbol: "externaldrive.fill") {
            VStack(alignment: .leading, spacing: Space.s12) {
                Text("Resets the count of items filtered this week back to zero.")
                    .font(TypeRole.footnote)
                    .foregroundStyle(Theme.color.textMuted)

                Button("Delete weekly insight data", role: .destructive, action: deleteInsightsAction)
                    .buttonStyle(.app(.secondary, .md))

                Divider()
                    .foregroundStyle(Theme.color.border)
                    .padding(.vertical, Space.s4)

                Text("Signs you out of every platform in QuietFeed, clears your weekly insights and resets every switch, as on first launch. Your accounts on those platforms themselves aren't touched.")
                    .font(TypeRole.footnote)
                    .foregroundStyle(Theme.color.textMuted)

                Button("Delete my data", role: .destructive, action: deleteAction)
                    .buttonStyle(.app(.danger, .md))
            }
        }
    }
}

#Preview("Stats") { StatsScreen().previewEnvironment() }
#Preview("Blocking") { BlockingScreen().previewEnvironment() }
#Preview("Settings") { SettingsScreen().previewEnvironment() }
#Preview("Accounts") {
    AccountsScreen(platform: PreviewSupport.rules.platforms[0]).previewEnvironment()
}
