import Foundation
import Observation
#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
@Observable
final class FocusSessionStore {
    private enum Key {
        static let endDate = "focusSessionEndDate"
        static let blockPlatforms = "focusBlocksQuietFeedPlatforms"
        static let notifications = "focusCompletionNotifications"
    }

    private(set) var endDate: Date?
    var blocksPlatforms: Bool {
        didSet { defaults.set(blocksPlatforms, forKey: Key.blockPlatforms) }
    }
    var completionNotifications: Bool {
        didSet { defaults.set(completionNotifications, forKey: Key.notifications) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedEnd = defaults.object(forKey: Key.endDate) as? Date
        endDate = savedEnd.flatMap { $0 > .now ? $0 : nil }
        blocksPlatforms = defaults.object(forKey: Key.blockPlatforms) as? Bool ?? true
        completionNotifications = defaults.object(forKey: Key.notifications) as? Bool ?? false
    }

    var isActive: Bool {
        guard let endDate else { return false }
        return endDate > .now
    }

    func remaining(at date: Date = .now) -> TimeInterval {
        max(0, endDate?.timeIntervalSince(date) ?? 0)
    }

    func start(minutes: Int) async {
        let end = Date.now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        endDate = end
        defaults.set(end, forKey: Key.endDate)
        if completionNotifications {
            await scheduleCompletionNotification(after: TimeInterval(max(1, minutes) * 60))
        }
    }

    func stop() {
        endDate = nil
        defaults.removeObject(forKey: Key.endDate)
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["quietfeed.focus.complete"])
        #endif
    }

    func setNotificationsEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else {
            completionNotifications = false
            return true
        }
        #if canImport(UserNotifications)
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            completionNotifications = granted
            return granted
        } catch {
            completionNotifications = false
            return false
        }
        #else
        completionNotifications = false
        return false
        #endif
    }

    private func scheduleCompletionNotification(after interval: TimeInterval) async {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "Focus session complete"
        content.body = "Your QuietFeed focus time is finished."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let request = UNNotificationRequest(identifier: "quietfeed.focus.complete", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
        #endif
    }
}

struct PlatformUsageRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var platformID: String
    var startedAt: Date
    var endedAt: Date

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

@MainActor
@Observable
final class UsageStore {
    private(set) var records: [PlatformUsageRecord] = []
    private var activePlatformID: String?
    private var activeStart: Date?
    private let fileURL: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        let folder = directory ?? (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory).appendingPathComponent("QuietFeed", isDirectory: true)
        fileURL = folder.appendingPathComponent("usage-sessions.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([PlatformUsageRecord].self, from: data) {
            records = saved
        }
    }

    func begin(platformID: String, at date: Date = .now) {
        guard activePlatformID != platformID else { return }
        end(at: date)
        activePlatformID = platformID
        activeStart = date
    }

    func end(at date: Date = .now) {
        guard let platformID = activePlatformID, let startedAt = activeStart, date > startedAt else {
            activePlatformID = nil
            activeStart = nil
            return
        }
        records.append(PlatformUsageRecord(id: UUID(), platformID: platformID, startedAt: startedAt, endedAt: date))
        records = Array(records.suffix(2_000))
        activePlatformID = nil
        activeStart = nil
        persist()
    }

    func duration(platformID: String? = nil, since start: Date) -> TimeInterval {
        records.lazy
            .filter { $0.endedAt >= start && (platformID == nil || $0.platformID == platformID) }
            .reduce(0) { $0 + $1.duration }
    }

    func exportCSV(platformName: (String) -> String) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["platform,started_at,ended_at,duration_seconds"]
        lines += records.map {
            "\(csv(platformName($0.platformID))),\(formatter.string(from: $0.startedAt)),\(formatter.string(from: $0.endedAt)),\(Int($0.duration))"
        }
        return lines.joined(separator: "\n")
    }

    func reset() {
        records = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Unable to persist usage sessions: \(error)")
        }
    }

    private func csv(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
