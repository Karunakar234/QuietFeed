import XCTest
@testable import QuietFeed

/// Regression benchmarks for the work QuietFeed does on every launch and every navigation.
/// Swift Testing has no `measure`, so these use XCTest. Set a baseline in Xcode's test
/// report (Edit Baseline) to make a slowdown fail the run; until then they only record timings.
@MainActor
final class PerformanceBenchmarks: XCTestCase {
    /// Decoding the bundled rules happens before the first frame (see `StillfeedApp`).
    func testBundledRulesDecode() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            XCTAssertFalse(BundledRuleProvider.loadNow().platforms.isEmpty)
        }
    }

    /// Every main-frame and subframe navigation goes through `NavigationGuard.decide`.
    func testNavigationGuardDecisions() throws {
        let ruleSet = BundledRuleProvider.loadNow()
        let store = RuleStore(provider: BundledRuleProvider(), preloaded: ruleSet)
        let youtube = try XCTUnwrap(ruleSet.platforms.first { $0.id == "youtube" })
        let guardian = NavigationGuard(platform: youtube, rules: store.enabledRules(for: youtube.id, toggles: [:]))
        let urls = (0..<1_000).compactMap { i in
            URL(string: i.isMultiple(of: 3) ? "https://m.youtube.com/shorts/\(i)" : "https://m.youtube.com/watch?v=\(i)")
        }
        measure(metrics: [XCTClockMetric()]) {
            for url in urls { _ = guardian.decide(url: url, isMainFrame: true) }
        }
    }

    /// Home's search runs on every keystroke.
    func testLocalSearch() {
        let ruleSet = BundledRuleProvider.loadNow()
        let store = RuleStore(provider: BundledRuleProvider(), preloaded: ruleSet)
        let tracks = (0..<2_000).map { OfflineTrack(id: UUID(), title: "Track \($0)", fileName: "\($0).m4a", importedAt: .now) }
        measure(metrics: [XCTClockMetric()]) {
            for query in ["s", "sh", "sho", "shorts", "track 19"] {
                _ = LocalSearch.filters(matching: query, platforms: ruleSet.platforms, toggles: store.toggles(for:))
                _ = LocalSearch.tracks(matching: query, in: tracks)
            }
        }
    }
}
