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
        static let enabled = "focusModeEnabled"
        static let blockPlatforms = "focusBlocksQuietFeedPlatforms"
        static let notifications = "focusCompletionNotifications"
        static let pausedRemaining = "focusPausedRemaining"
    }

    private(set) var endDate: Date?
    private(set) var isEnabled: Bool
    private(set) var pausedRemaining: TimeInterval
    var blocksPlatforms: Bool {
        didSet { defaults.set(blocksPlatforms, forKey: Key.blockPlatforms) }
    }
    var completionNotifications: Bool {
        didSet { defaults.set(completionNotifications, forKey: Key.notifications) }
    }

    private let defaults: UserDefaults
    /// Whether this store drives the widget and Live Activity. Only the app's own store does;
    /// tests and previews pass their own defaults and leave the system untouched.
    private let publishesToSystem: Bool

    init(defaults: UserDefaults = .standard, publishesToSystem: Bool? = nil) {
        self.defaults = defaults
        self.publishesToSystem = publishesToSystem ?? (defaults === UserDefaults.standard)
        let savedEnd = defaults.object(forKey: Key.endDate) as? Date
        endDate = savedEnd.flatMap { $0 > .now ? $0 : nil }
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        blocksPlatforms = defaults.object(forKey: Key.blockPlatforms) as? Bool ?? true
        completionNotifications = defaults.object(forKey: Key.notifications) as? Bool ?? false
        pausedRemaining = max(0, defaults.double(forKey: Key.pausedRemaining))
        // Brings the widget in line after a relaunch and ends a Live Activity whose session
        // finished while the app wasn't running.
        publish()
    }

    private func publish() {
        guard publishesToSystem else { return }
        FocusSurfaces.publish(endDate: endDate, isEnabled: isEnabled)
    }

    var isActive: Bool {
        guard isEnabled, let endDate else { return false }
        return endDate > .now
    }

    var isPaused: Bool { isEnabled && pausedRemaining > 0 && endDate == nil }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Key.enabled)
        if enabled { publish() } else { stop() }
    }

    func remaining(at date: Date = .now) -> TimeInterval {
        isPaused ? pausedRemaining : max(0, endDate?.timeIntervalSince(date) ?? 0)
    }

    func start(minutes: Int) async {
        guard isEnabled else { return }
        let duration = TimeInterval(max(1, minutes) * 60)
        let end = Date.now.addingTimeInterval(duration)
        pausedRemaining = 0
        defaults.removeObject(forKey: Key.pausedRemaining)
        endDate = end
        defaults.set(end, forKey: Key.endDate)
        publish()
        if completionNotifications {
            await scheduleCompletionNotification(after: duration)
        }
    }

    func pause() {
        guard isActive else { return }
        pausedRemaining = remaining()
        endDate = nil
        defaults.set(pausedRemaining, forKey: Key.pausedRemaining)
        defaults.removeObject(forKey: Key.endDate)
        publish()
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["quietfeed.focus.complete"])
        #endif
    }

    func resume() async {
        guard isPaused else { return }
        let remaining = pausedRemaining
        pausedRemaining = 0
        defaults.removeObject(forKey: Key.pausedRemaining)
        let end = Date.now.addingTimeInterval(remaining)
        endDate = end
        defaults.set(end, forKey: Key.endDate)
        publish()
        if completionNotifications { await scheduleCompletionNotification(after: remaining) }
    }

    func stop() {
        endDate = nil
        pausedRemaining = 0
        defaults.removeObject(forKey: Key.endDate)
        defaults.removeObject(forKey: Key.pausedRemaining)
        publish()
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["quietfeed.focus.complete"])
        #endif
    }

    func setNotificationsEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else {
            completionNotifications = false
            #if canImport(UserNotifications)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["quietfeed.focus.complete"])
            #endif
            return true
        }
        #if canImport(UserNotifications)
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            completionNotifications = granted
            if granted, isActive, let remaining = endDate?.timeIntervalSinceNow, remaining > 0 {
                await scheduleCompletionNotification(after: remaining)
            }
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

    func duration(platformID: String? = nil, since start: Date, now: Date = .now) -> TimeInterval {
        var total = records.lazy
            .filter { $0.endedAt >= start && (platformID == nil || $0.platformID == platformID) }
            .reduce(0) { $0 + $1.duration }
        if let activeID = activePlatformID, let activeStart, now > activeStart {
            if platformID == nil || activeID == platformID {
                let effectiveStart = max(activeStart, start)
                if now > effectiveStart {
                    total += now.timeIntervalSince(effectiveStart)
                }
            }
        }
        return total
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
