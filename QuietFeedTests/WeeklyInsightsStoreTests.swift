import Foundation
import Testing
@testable import QuietFeed

/// Weekly insights: one week of counts in a small JSON file. Every test uses its own
/// temporary folder, so the app's real data is never read or changed.
@Suite struct WeeklyInsightsStoreTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuietFeedTests-\(UUID().uuidString)", isDirectory: true)
    private var file: URL { folder.appendingPathComponent("weekly-insights.json") }

    /// Wednesday 18 November 2026, midday local time.
    private let wednesday: Date = {
        var parts = DateComponents(year: 2026, month: 11, day: 18, hour: 12)
        parts.timeZone = .current
        return Calendar(identifier: .iso8601).date(from: parts) ?? .now
    }()

    private func day(_ offset: Int) -> Date {
        wednesday.addingTimeInterval(Double(offset) * 86_400)
    }

    @Test func countsLandOnTheirDay() {
        let store = WeeklyInsightsStore(directory: folder, now: wednesday)
        store.recordHidden(3, at: wednesday)
        store.recordHidden(2, at: wednesday)
        store.recordHidden(4, at: day(1))
        // ISO weeks start on Monday, so Wednesday is index 2.
        #expect(store.dailyCounts == [0, 0, 5, 4, 0, 0, 0])
        #expect(store.totalHidden == 9)
    }

    @Test func zeroAndNegativeCountsAreIgnored() {
        let store = WeeklyInsightsStore(directory: folder, now: wednesday)
        store.recordHidden(0, at: wednesday)
        store.recordHidden(-5, at: wednesday)
        #expect(store.totalHidden == 0)
    }

    @Test func aNewWeekStartsAtZero() {
        let store = WeeklyInsightsStore(directory: folder, now: wednesday)
        store.recordHidden(7, at: wednesday)
        store.recordHidden(1, at: day(7))
        #expect(store.totalHidden == 1)
    }

    @Test func countsSurviveARestart() {
        let first = WeeklyInsightsStore(directory: folder, now: .now)
        first.recordHidden(6)
        first.flush()
        let second = WeeklyInsightsStore(directory: folder, now: .now)
        #expect(second.totalHidden == 6)
    }

    @Test func aDamagedFileStartsFresh() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        let store = WeeklyInsightsStore(directory: folder, now: .now)
        #expect(store.totalHidden == 0)
    }

    @Test func resetDeletesTheFile() {
        let store = WeeklyInsightsStore(directory: folder, now: .now)
        store.recordHidden(2)
        store.flush()
        #expect(FileManager.default.fileExists(atPath: file.path))
        store.reset()
        #expect(store.totalHidden == 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
