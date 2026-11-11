import Foundation

/// Decides, natively, where a page load may go. It backs up the injected engine:
/// even if a page's markup changes, blocked places stay blocked.
struct NavigationGuard {
    enum Decision: Equatable {
        case allow
        case redirect(URL)
        case external(URL)
        case cancel
    }

    let platform: Platform
    let rules: [FilterRule]

    func decide(url: URL, isMainFrame: Bool) -> Decision {
        let scheme = url.scheme?.lowercased() ?? ""
        if ["about", "blob", "data"].contains(scheme) { return .allow }
        guard scheme == "https" || scheme == "http" else { return .cancel }
        guard isMainFrame else { return .allow }
        guard let host = url.host?.lowercased(), isAllowed(host: host) else { return .external(url) }
        guard isPlatformHost(host) else { return .allow }

        let path = Self.pathAndQuery(of: url)
        for rule in rules {
            guard rule.action == FilterRule.Action.redirect || rule.action == FilterRule.Action.blockNavigation else { continue }
            guard let regex = Self.firstMatch(rule.urlPatterns ?? [], in: path) else { continue }
            let target: String
            if rule.action == FilterRule.Action.redirect {
                let range = NSRange(path.startIndex..., in: path)
                target = regex.stringByReplacingMatches(in: path, range: range, withTemplate: rule.redirectTo ?? "/")
            } else {
                target = "/"
            }
            if target != path, let destination = URL(string: target, relativeTo: platform.baseUrl)?.absoluteURL {
                return .redirect(destination)
            }
        }
        return .allow
    }

    /// True on a page that should show one item only (a reel a friend sent).
    func isSingleItem(url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased(), isPlatformHost(host) else { return false }
        let path = Self.pathAndQuery(of: url)
        return rules.contains { rule in
            rule.action == FilterRule.Action.disableScroll && Self.firstMatch(rule.urlPatterns ?? [], in: path) != nil
        }
    }

    private func isAllowed(host: String) -> Bool {
        platform.allowedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private func isPlatformHost(_ host: String) -> Bool {
        guard let own = platform.allowedHosts.first else { return false }
        return host == own || host.hasSuffix("." + own)
    }

    /// URL.path drops a trailing slash, so read the path from components instead.
    static func pathAndQuery(of url: URL) -> String {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: true)
        var path = parts?.percentEncodedPath ?? url.path
        if path.isEmpty { path = "/" }
        if let query = parts?.percentEncodedQuery, !query.isEmpty { path += "?" + query }
        return path
    }

    static func firstMatch(_ patterns: [String], in path: String) -> NSRegularExpression? {
        let range = NSRange(path.startIndex..., in: path)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            if regex.firstMatch(in: path, range: range) != nil { return regex }
        }
        return nil
    }
}
