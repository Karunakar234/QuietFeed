import CryptoKit
import WebKit

/// Blocks known ad requests natively, before they download. The rules are bundled with the app,
/// not fetched from a server, so they're reviewed with each release like FilterEngine.js.
/// This covers ad networks and YouTube's ad-tracking endpoints. It can't stop ads that YouTube
/// serves from the same host as the video itself.
enum AdBlocker {
    /// Includes a fingerprint of the rules, so editing them compiles a fresh list
    /// instead of reusing a stale one from WebKit's store.
    private static let identifier: String = {
        let digest = SHA256.hash(data: Data(rules.utf8))
        return "quietfeed-ads-" + digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }()

    /// The compiled rules, kept after the first page so later pages attach them instantly.
    private static var compiled: WKContentRuleList?

    private static let rules = #"""
    [
      {"trigger": {"url-filter": "^https?://([a-z0-9-]+\\.)*doubleclick\\.net/"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^https?://([a-z0-9-]+\\.)*googlesyndication\\.com/"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^https?://([a-z0-9-]+\\.)*googleadservices\\.com/"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/pagead/"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/api/stats/ads"}, "action": {"type": "block"}}
    ]
    """#

    /// Attaches the rules to a page's controller. Pages wait for this before loading,
    /// so it has to be quick: compiling on every open used to hold each page up by seconds.
    static func install(into controller: WKUserContentController) async {
        if let list = await ruleList() { controller.add(list) }
    }

    /// From memory if already loaded; else from WebKit's on-disk store (saved by an earlier
    /// launch); compiled only when neither has this version of the rules.
    private static func ruleList() async -> WKContentRuleList? {
        if let compiled { return compiled }
        let store = WKContentRuleListStore.default()
        if let saved = try? await store?.contentRuleList(forIdentifier: identifier) {
            compiled = saved
            return saved
        }
        do {
            let list = try await store?.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules)
            compiled = list
            return list
        } catch {
            assertionFailure("Ad block rules failed to compile: \(error)")
            return nil
        }
    }
}
