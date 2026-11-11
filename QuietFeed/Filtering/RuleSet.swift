import Foundation

/// A platform Stillfeed can open. Decoded from rules.json (snake_case keys).
struct Platform: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let baseUrl: URL
    let allowedHosts: [String]
    let symbol: String
    let tagline: String?
    let isPro: Bool
}

/// One filter rule. Rules are data: selectors, patterns and an action from a fixed set.
struct FilterRule: Codable, Hashable {
    enum Action {
        static let hide = "hide"
        static let remove = "remove"
        static let redirect = "redirect"
        static let blockNavigation = "block_navigation"
        static let disableScroll = "disable_scroll"
        static let skipAds = "skip_ads"
    }

    let platformId: String
    let key: String
    let title: String
    let detail: String?
    let action: String
    let selectors: [String]?
    let urlPatterns: [String]?
    let textMatches: [String]?
    let redirectTo: String?
    let isPro: Bool
    let defaultOn: Bool
}

struct RuleSet: Codable {
    let version: Int
    let platforms: [Platform]
    let rules: [FilterRule]

    static let empty = RuleSet(version: 0, platforms: [], rules: [])
}

/// What the Filters screen shows: one switch per rule key (a key can cover several rules).
struct RuleToggle: Identifiable, Hashable {
    let key: String
    let title: String
    let detail: String?
    let isPro: Bool
    let defaultOn: Bool
    var id: String { key }
}

extension JSONDecoder {
    static var rules: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}

extension JSONEncoder {
    static var rules: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}
