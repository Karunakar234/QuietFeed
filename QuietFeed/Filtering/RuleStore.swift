import Foundation
import Observation

/// Where rules come from. Today: the copy bundled in the app. /replica-backend adds a
/// remote provider with this same signature, so no screen code changes.
protocol RuleProviding {
    func loadRules() async -> RuleSet
}

struct BundledRuleProvider: RuleProviding {
    func loadRules() async -> RuleSet {
        Self.loadNow()
    }

    /// Reads the bundled rules straight away. The file is small, so the app can have its
    /// rules before the first frame and open on Home instead of a loading screen.
    static func loadNow() -> RuleSet {
        guard let url = Bundle.main.url(forResource: "rules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let set = try? JSONDecoder.rules.decode(RuleSet.self, from: data) else {
            assertionFailure("rules.json missing or invalid")
            return .empty
        }
        return set
    }
}

@MainActor
@Observable
final class RuleStore {
    private let provider: RuleProviding
    private(set) var ruleSet: RuleSet?

    /// `preloaded` lets the app start with rules already in hand (no loading screen).
    init(provider: RuleProviding, preloaded: RuleSet? = nil) {
        self.provider = provider
        self.ruleSet = preloaded
    }

    func load() async {
        ruleSet = await provider.loadRules()
    }

    var isLoaded: Bool { ruleSet != nil }
    var platforms: [Platform] { ruleSet?.platforms ?? [] }

    func platform(id: String) -> Platform? {
        platforms.first { $0.id == id }
    }

    func rules(for platformID: String) -> [FilterRule] {
        (ruleSet?.rules ?? []).filter { $0.platformId == platformID }
    }

    /// One switch per key, in file order.
    func toggles(for platformID: String) -> [RuleToggle] {
        var seen = Set<String>()
        var out: [RuleToggle] = []
        for rule in rules(for: platformID) where seen.insert(rule.key).inserted {
            let detail = rules(for: platformID).first { $0.key == rule.key && $0.detail != nil }?.detail
            out.append(RuleToggle(key: rule.key, title: rule.title, detail: detail, isPro: rule.isPro, defaultOn: rule.defaultOn))
        }
        return out
    }

    /// The rules to run, given the person's switches. Core rules are never locked.
    func enabledRules(for platformID: String, toggles: [String: Bool]) -> [FilterRule] {
        rules(for: platformID).filter { toggles[$0.key] ?? $0.defaultOn }
    }
}
