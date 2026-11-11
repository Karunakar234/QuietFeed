import WebKit

/// Blocks known ad requests natively, before they download. The rules are bundled with the app,
/// not fetched from a server, so they're reviewed with each release like FilterEngine.js.
/// This covers ad networks and YouTube's ad-tracking endpoints. It can't stop ads that YouTube
/// serves from the same host as the video itself.
enum AdBlocker {
    private static let identifier = "quietfeed-ads"

    private static let rules = #"""
    [
      {"trigger": {"url-filter": "^https?://([a-z0-9-]+\\.)*doubleclick\\.net/"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^https?://([a-z0-9-]+\\.)*googlesyndication\\.com/"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^https?://([a-z0-9-]+\\.)*googleadservices\\.com/"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/pagead/"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/api/stats/ads"}, "action": {"type": "block"}}
    ]
    """#

    /// Compiles the bundled rules once (WebKit caches the result) and attaches them to the controller.
    static func install(into controller: WKUserContentController) async {
        do {
            if let list = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier, encodedContentRuleList: rules) {
                controller.add(list)
            }
        } catch {
            assertionFailure("Ad block rules failed to compile: \(error)")
        }
    }
}
