import Foundation
import Observation

struct WeeklyInsightSnapshot: Codable {
    var weekStart: Date
    var dailyHiddenCounts: [Int]
}

/// Keeps only the current calendar week's filtering totals in a small JSON file.
@MainActor
@Observable
final class WeeklyInsightsStore {
    private(set) var snapshot: WeeklyInsightSnapshot

    private let fileURL: URL
    private let fileManager: FileManager
    private let calendar: Calendar
    /// The filter engine reports every few dozen milliseconds while a page scrolls, so saves
    /// are batched: at most one write every couple of seconds, plus flush() on backgrounding.
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    private static let saveDelay: Duration = .seconds(2)

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        self.calendar = calendar

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let directory = applicationSupport.appendingPathComponent("QuietFeed", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("weekly-insights.json")

        let currentWeekStart = Self.weekStart(for: .now, calendar: calendar)
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(WeeklyInsightSnapshot.self, from: data),
           calendar.isDate(saved.weekStart, inSameDayAs: currentWeekStart),
           saved.dailyHiddenCounts.count == 7 {
            snapshot = saved
        } else {
            snapshot = WeeklyInsightSnapshot(
                weekStart: currentWeekStart,
                dailyHiddenCounts: Array(repeating: 0, count: 7)
            )
            persist()
        }
    }

    var dailyCounts: [Int] {
        snapshot.dailyHiddenCounts
    }

    var totalHidden: Int {
        dailyCounts.reduce(0, +)
    }

    func refresh(for date: Date = .now) {
        let currentWeekStart = Self.weekStart(for: date, calendar: calendar)
        guard !calendar.isDate(snapshot.weekStart, inSameDayAs: currentWeekStart) else {
            return
        }

        snapshot = WeeklyInsightSnapshot(
            weekStart: currentWeekStart,
            dailyHiddenCounts: Array(repeating: 0, count: 7)
        )
        persist()
    }

    func recordHidden(_ count: Int, at date: Date = .now) {
        guard count > 0 else { return }
        refresh(for: date)

        let day = calendar.dateComponents(
            [.day],
            from: snapshot.weekStart,
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        guard snapshot.dailyHiddenCounts.indices.contains(day) else { return }

        snapshot.dailyHiddenCounts[day] += count
        scheduleSave()
    }

    /// Writes any batched count now. Called when the app leaves the foreground.
    func flush() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        persist()
    }

    private func scheduleSave() {
        guard pendingSave == nil else { return }
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard let self, !Task.isCancelled else { return }
            self.pendingSave = nil
            self.persist()
        }
    }

    /// Deletes the saved file and starts this week over at zero ("Delete my data" in Settings).
    func reset() {
        pendingSave?.cancel()
        pendingSave = nil
        try? fileManager.removeItem(at: fileURL)
        snapshot = WeeklyInsightSnapshot(
            weekStart: Self.weekStart(for: .now, calendar: calendar),
            dailyHiddenCounts: Array(repeating: 0, count: 7)
        )
    }

    private func persist() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Unable to save weekly insights: \(error)")
        }
    }

    private static func weekStart(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }
}
