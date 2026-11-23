import AppIntents
import Foundation
import Observation

/// Hands "Open a platform" requests from Siri and Shortcuts to the running UI.
@MainActor
@Observable
final class IntentRouter {
    /// Set by an intent; RootView opens it and clears it.
    var pendingPlatformID: String?
}

/// A platform, as Siri and Shortcuts see it. `id` is the platform's id from rules.json,
/// which is stable across launches and devices.
struct PlatformEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Platform"
    static let defaultQuery = PlatformEntityQuery()

    let id: String
    let name: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

struct PlatformEntityQuery: EntityQuery {
    private func allPlatforms() async -> [PlatformEntity] {
        await MainActor.run {
            BundledRuleProvider.loadNow().platforms.map {
                PlatformEntity(id: $0.id, name: $0.name, symbol: $0.symbol)
            }
        }
    }

    func entities(for identifiers: [String]) async throws -> [PlatformEntity] {
        let wanted = Set(identifiers)
        return await allPlatforms().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PlatformEntity] {
        await allPlatforms()
    }
}

enum QuietFeedIntentError: Error, CustomLocalizedStringResourceConvertible {
    case focusDisabled
    case focusBlocksPlatforms
    case unknownPlatform

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .focusDisabled: "Focus Mode is turned off in QuietFeed's Settings."
        case .focusBlocksPlatforms: "A focus session is active, so platforms can't be opened in QuietFeed right now."
        case .unknownPlatform: "QuietFeed doesn't know that platform."
        }
    }
}

struct StartFocusSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus Session"
    static let description = IntentDescription("Starts a QuietFeed focus session. Platforms can be blocked inside QuietFeed until it ends.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Minutes", default: 25, inclusiveRange: (1, 240))
    var minutes: Int

    @Dependency private var focus: FocusSessionStore

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute focus session")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let enabled = await focus.isEnabled
        guard enabled else { throw QuietFeedIntentError.focusDisabled }
        await focus.start(minutes: minutes)
        return .result(dialog: "Focus session started for \(minutes) minutes.")
    }
}

struct EndFocusSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "End Focus Session"
    static let description = IntentDescription("Ends the current QuietFeed focus session.")
    static var supportedModes: IntentModes { .background }

    @Dependency private var focus: FocusSessionStore

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await focus.stop()
        return .result(dialog: "Focus session ended.")
    }
}

struct OpenPlatformIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Platform"
    static let description = IntentDescription("Opens a platform in QuietFeed with your filters on.")
    // The platform appears on screen, so the app must be in front before perform() runs.
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Platform")
    var platform: PlatformEntity

    @Dependency private var focus: FocusSessionStore
    @Dependency private var router: IntentRouter

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$platform)")
    }

    func perform() async throws -> some IntentResult {
        let blocked = await MainActor.run { focus.isActive && focus.blocksPlatforms }
        guard !blocked else { throw QuietFeedIntentError.focusBlocksPlatforms }
        let id = platform.id
        await MainActor.run { router.pendingPlatformID = id }
        return .result()
    }
}

struct QuietFeedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusSessionIntent(),
            phrases: [
                "Start a focus session in \(.applicationName)",
                "Start focusing with \(.applicationName)"
            ],
            shortTitle: "Start Focus",
            systemImageName: "leaf.fill"
        )
        AppShortcut(
            intent: EndFocusSessionIntent(),
            phrases: ["End my focus session in \(.applicationName)"],
            shortTitle: "End Focus",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: OpenPlatformIntent(),
            phrases: [
                "Open \(\.$platform) in \(.applicationName)",
                "Open a platform in \(.applicationName)"
            ],
            shortTitle: "Open Platform",
            systemImageName: "play.rectangle"
        )
    }
}

#if os(iOS)
/// Lets "Start Focus Session" begin the Focus Live Activity when Siri or Shortcuts runs it
/// with QuietFeed in the background.
extension StartFocusSessionIntent: LiveActivityIntent {}
#endif
