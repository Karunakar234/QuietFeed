import Foundation
import Testing
@testable import QuietFeed

/// The native half of the navigation rules: what a page load may do, per platform.
@Suite struct NavigationGuardTests {
    private let store: RuleStore

    init() async {
        store = RuleStore(provider: BundledRuleProvider())
        await store.load()
    }

    private func navGuard(_ platformID: String, toggles: [String: Bool] = [:]) throws -> NavigationGuard {
        let platform = try #require(store.platform(id: platformID))
        return NavigationGuard(platform: platform, rules: store.enabledRules(for: platformID, toggles: toggles))
    }

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    @Test func platformPagesLoadInTheApp() throws {
        let youtube = try navGuard("youtube")
        #expect(youtube.decide(url: try url("https://m.youtube.com/watch?v=abc"), isMainFrame: true) == .allow)
        #expect(youtube.decide(url: try url("https://accounts.google.com/signin"), isMainFrame: true) == .allow)
    }

    @Test func otherSitesOpenOutsideTheApp() throws {
        let instagram = try navGuard("instagram")
        let outside = try url("https://example.com/article")
        #expect(instagram.decide(url: outside, isMainFrame: true) == .external(outside))
    }

    @Test func subframesFromOtherHostsAreAllowed() throws {
        let youtube = try navGuard("youtube")
        #expect(youtube.decide(url: try url("https://www.gstatic.com/frame"), isMainFrame: false) == .allow)
    }

    @Test(arguments: ["music://open", "itms-apps://apps.apple.com/app/id1", "javascript:alert(1)", "file:///etc/hosts"])
    func appSchemesAndLocalFilesAreCancelled(_ link: String) throws {
        let music = try navGuard("youtube_music")
        #expect(music.decide(url: try url(link), isMainFrame: true) == .cancel)
    }

    @Test func shortsBecomeTheNormalWatchPage() throws {
        let youtube = try navGuard("youtube")
        let decision = youtube.decide(url: try url("https://m.youtube.com/shorts/abc_123"), isMainFrame: true)
        #expect(decision == .redirect(try url("https://m.youtube.com/watch?v=abc_123")))
    }

    @Test func turningASwitchOffLetsThePageOpen() throws {
        let instagram = try navGuard("instagram", toggles: ["hide_reels": false])
        #expect(instagram.decide(url: try url("https://www.instagram.com/reels/"), isMainFrame: true) == .allow)
    }

    @Test func aReelFromAFriendIsASingleItem() throws {
        let instagram = try navGuard("instagram")
        #expect(instagram.isSingleItem(url: try url("https://www.instagram.com/reel/AbC-12/")))
        #expect(!instagram.isSingleItem(url: try url("https://www.instagram.com/")))
    }

    @Test(arguments: ["https://www.amazon.co.uk/ap/signin", "https://www.amazon.de/ap/signin", "https://www.amazon.in/ap/signin"])
    func primeVideoRegionalSignInStaysInTheApp(_ link: String) throws {
        let prime = try navGuard("amazon_prime")
        #expect(prime.decide(url: try url(link), isMainFrame: true) == .allow)
    }

    @Test func lookalikeHostsAreNotTreatedAsThePlatform() throws {
        let youtube = try navGuard("youtube")
        let lookalike = try url("https://notyoutube.com/watch")
        #expect(youtube.decide(url: lookalike, isMainFrame: true) == .external(lookalike))
    }
}

/// The Filters screen's switches and the rules they turn on.
@Suite struct RuleStoreTests {
    @Test func bundledRulesLoad() async {
        let store = RuleStore(provider: BundledRuleProvider())
        await store.load()
        #expect(store.isLoaded)
        #expect(store.platform(id: "youtube_music") != nil)
    }

    @Test func switchesFollowDefaultsUntilChanged() async {
        let store = RuleStore(provider: BundledRuleProvider())
        await store.load()
        let defaults = Set(store.enabledRules(for: "youtube", toggles: [:]).map(\.key))
        #expect(defaults.contains("hide_header"))
        #expect(!defaults.contains("hide_footer"))

        let changed = Set(store.enabledRules(for: "youtube", toggles: ["hide_header": false, "hide_footer": true]).map(\.key))
        #expect(!changed.contains("hide_header"))
        #expect(changed.contains("hide_footer"))
    }

    @Test func oneSwitchPerKey() async {
        let store = RuleStore(provider: BundledRuleProvider())
        await store.load()
        for platform in store.platforms {
            let keys = store.toggles(for: platform.id).map(\.key)
            #expect(keys.count == Set(keys).count, "\(platform.id) has duplicate switches")
        }
    }

    /// YouTube Music's "open the app" pop-up must be dismissed, never hidden: a hidden modal
    /// leaves the page inert and every tap on a song is ignored.
    @Test func youtubeMusicPopUpsAreNotHiddenWithCSS() async {
        let store = RuleStore(provider: BundledRuleProvider())
        await store.load()
        let modalSelectors = ["tp-yt-paper-dialog", "ytmusic-mealbar-promo-renderer", "[role=\"dialog\"]"]
        for rule in store.rules(for: "youtube_music") where rule.action == FilterRule.Action.hide {
            for selector in rule.selectors ?? [] {
                #expect(!modalSelectors.contains(selector), "\(rule.key) hides \(selector)")
            }
        }
    }
}
