import Foundation
import Testing
@testable import QuietFeed

private func makeDefaults() -> (UserDefaults, String) {
    let suiteName = "QuietFeedTests.Reliability.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suiteName)!, suiteName)
}

@Suite struct LoadFailurePolicyTests {
    @Test func cancelledLoadsAreIgnored() {
        #expect(LoadFailurePolicy.outcome(domain: NSURLErrorDomain, code: NSURLErrorCancelled, attempt: 0) == .ignore)
        #expect(LoadFailurePolicy.outcome(domain: "WebKitErrorDomain", code: 102, attempt: 0) == .ignore)
    }

    @Test(arguments: [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed])
    func noConnectionIsOffline(code: Int) {
        #expect(LoadFailurePolicy.outcome(domain: NSURLErrorDomain, code: code, attempt: 0) == .offline)
    }

    @Test func transientErrorsRetryWithBackoffThenFail() {
        let code = NSURLErrorTimedOut
        #expect(LoadFailurePolicy.outcome(domain: NSURLErrorDomain, code: code, attempt: 0) == .retry(after: .seconds(2)))
        #expect(LoadFailurePolicy.outcome(domain: NSURLErrorDomain, code: code, attempt: 1) == .retry(after: .seconds(6)))
        #expect(LoadFailurePolicy.outcome(domain: NSURLErrorDomain, code: code, attempt: 2) == .fail)
    }

    @Test func otherErrorsFailStraightAway() {
        #expect(LoadFailurePolicy.outcome(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, attempt: 0) == .fail)
        #expect(LoadFailurePolicy.outcome(domain: "WebKitErrorDomain", code: 101, attempt: 0) == .fail)
    }
}

@MainActor
@Suite struct PlayerSessionRecoveryTests {
    private func platform(_ id: String) -> Platform {
        Platform(id: id, name: id, baseUrl: URL(string: "https://\(id).example")!, allowedHosts: ["\(id).example"],
                 symbol: "play", tagline: nil, isPro: false)
    }

    @Test func anOpenPlatformIsOfferedAfterARelaunch() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        PlayerSession(defaults: defaults).open(platform("youtube"))
        // A new session stands in for the next launch.
        #expect(PlayerSession(defaults: defaults).recoveryPlatformID == "youtube")
    }

    @Test func closingOrDismissingClearsTheOffer() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let session = PlayerSession(defaults: defaults)
        session.open(platform("spotify"))
        session.close()
        #expect(PlayerSession(defaults: defaults).recoveryPlatformID == nil)

        PlayerSession(defaults: defaults).open(platform("spotify"))
        let relaunched = PlayerSession(defaults: defaults)
        relaunched.discardRecovery()
        #expect(relaunched.recoveryPlatformID == nil)
        #expect(PlayerSession(defaults: defaults).recoveryPlatformID == nil)
    }

    @Test func anOldOfferExpires() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("netflix", forKey: "recoverablePlatformID")
        defaults.set(Date.now.addingTimeInterval(-2 * 24 * 60 * 60), forKey: "recoverablePlatformSavedAt")
        #expect(PlayerSession(defaults: defaults).recoveryPlatformID == nil)
    }
}

@MainActor
@Suite struct AppLockTests {
    /// An authenticator that answers with `results` in order and counts its calls.
    private final class FakeAuth {
        var results: [Result<Void, AppLock.AuthError>]
        var calls = 0
        init(_ results: [Result<Void, AppLock.AuthError>]) { self.results = results }
        func callAsFunction(_ reason: String) async -> Result<Void, AppLock.AuthError> {
            calls += 1
            return results.isEmpty ? .failure(.failed) : results.removeFirst()
        }
    }

    @Test func offByDefaultAndNeverLocks() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let lock = AppLock(defaults: defaults) { _ in .success(()) }
        lock.lock()
        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
    }

    @Test func enablingNeedsASuccessfulUnlock() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let auth = FakeAuth([.failure(.unavailable), .success(())])
        let lock = AppLock(defaults: defaults) { await auth($0) }
        #expect(await lock.setEnabled(true) == false)
        #expect(!lock.isEnabled)
        #expect(lock.lastError == .unavailable)

        #expect(await lock.setEnabled(true))
        #expect(lock.isEnabled)
        #expect(!lock.isLocked)
        // The next launch starts locked.
        #expect(AppLock(defaults: defaults) { _ in .success(()) }.isLocked)
    }

    @Test func backgroundLocksAndCancellingDoesNotRepromptInALoop() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let auth = FakeAuth([.success(()), .failure(.cancelled), .success(())])
        let lock = AppLock(defaults: defaults) { await auth($0) }
        await lock.setEnabled(true)
        lock.lock()
        #expect(lock.isLocked)

        await lock.promptIfNeeded()   // cancelled
        await lock.promptIfNeeded()   // the prompt's own inactive/active bounce: no second prompt
        #expect(lock.isLocked)
        #expect(auth.calls == 2)

        await lock.unlock()           // the Unlock button
        #expect(!lock.isLocked)
    }

    @Test func resetTurnsTheLockOff() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let lock = AppLock(defaults: defaults) { _ in .success(()) }
        await lock.setEnabled(true)
        lock.reset()
        #expect(!lock.isEnabled)
        #expect(!AppLock(defaults: defaults) { _ in .success(()) }.isLocked)
    }
}

@MainActor
@Suite struct LocalSearchTests {
    private let platforms = BundledRuleProvider.loadNow().platforms
    private let store = RuleStore(provider: BundledRuleProvider(), preloaded: BundledRuleProvider.loadNow())

    @Test func findsFiltersByTitleAndPlatformName() throws {
        let youtube = try #require(platforms.first { $0.id == "youtube" })
        let firstToggle = try #require(store.toggles(for: "youtube").first)

        let byTitle = LocalSearch.filters(matching: firstToggle.title, platforms: platforms, toggles: store.toggles(for:))
        #expect(byTitle.contains { $0.platformID == "youtube" && $0.toggle.key == firstToggle.key })

        let byPlatform = LocalSearch.filters(matching: youtube.name, platforms: [youtube], toggles: store.toggles(for:))
        #expect(byPlatform.count == store.toggles(for: "youtube").count)
    }

    @Test func blankQueriesMatchNothing() {
        #expect(LocalSearch.filters(matching: "  ", platforms: platforms, toggles: store.toggles(for:)).isEmpty)
        #expect(LocalSearch.tracks(matching: "", in: [OfflineTrack(id: UUID(), title: "Song", fileName: "a.m4a", importedAt: .now)]).isEmpty)
    }

    @Test func tracksMatchCaseAndDiacriticInsensitively() {
        let track = OfflineTrack(id: UUID(), title: "Café Morning", fileName: "a.m4a", importedAt: .now)
        #expect(LocalSearch.tracks(matching: "cafe", in: [track]) == [track])
        #expect(LocalSearch.tracks(matching: "evening", in: [track]).isEmpty)
    }
}

@MainActor
@Suite struct PlatformCapabilitiesTests {
    private let platforms = BundledRuleProvider.loadNow().platforms

    @Test func offlineDownloadsAreNeverClaimed() {
        for platform in platforms {
            let features = PlatformCapabilities(platform: platform, filterCount: 1).features
            #expect(features.first { $0.title == "Offline downloads" }?.availability == .unavailable)
        }
    }

    @Test func videoFeaturesFollowTheWebViewConfiguration() throws {
        let youtube = try #require(platforms.first { $0.id == "youtube" })
        let instagram = try #require(platforms.first { $0.id == "instagram" })
        let fullScreen = { (p: Platform) in
            PlatformCapabilities(platform: p, filterCount: 0).features.first { $0.title == "Full-screen video" }?.availability
        }
        #expect(fullScreen(youtube) == .available)
        #expect(fullScreen(instagram) == .unavailable)
    }
}

@Suite struct LauncherLinkTests {
    @Test func bundledRegistryIsSafeAndComplete() {
        let platforms = BundledRuleProvider.loadNow().platforms
        let required = Set(["youtube", "youtube_music", "netflix", "amazon_prime", "spotify", "instagram"])
        #expect(required.isSubset(of: Set(platforms.map(\.id))))
        #expect(Set(platforms.map(\.id)).count == platforms.count)
        for platform in platforms {
            #expect(platform.baseUrl.scheme == "https")
            #expect(platform.baseUrl.host.map { host in
                platform.allowedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
            } == true)
        }
    }

    @Test func launchMetadataUsesSafeWebFirstBehavior() throws {
        let platforms = BundledRuleProvider.loadNow().platforms
        let prime = try #require(platforms.first { $0.id == "amazon_prime" })
        let youtube = try #require(platforms.first { $0.id == "youtube" })
        #expect(prime.preferredLaunchMethod == .websiteWithAppFallback)
        #expect(youtube.preferredLaunchMethod == .embeddedWebsite)
        #expect(platforms.allSatisfy { $0.deepLinkBehavior == .quietFeedRoute })
    }

    @Test func openLinksNameThePlatform() {
        #expect(LauncherSnapshot.platformID(from: URL(string: "quietfeed://open/youtube")!) == "youtube")
        #expect(LauncherSnapshot.platformID(from: URL(string: "quietfeed://open/amazon_prime")!) == "amazon_prime")
    }

    @Test(arguments: ["quietfeed://home", "quietfeed://open", "quietfeed://open/", "https://open/youtube", "other://open/youtube"])
    func otherLinksOpenNoPlatform(_ link: String) {
        #expect(LauncherSnapshot.platformID(from: URL(string: link)!) == nil)
    }
}
