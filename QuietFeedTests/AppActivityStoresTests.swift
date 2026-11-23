import Foundation
import Testing
@testable import QuietFeed

@Suite struct FocusSessionStoreTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "QuietFeedTests.Focus.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    @Test func startSessionActivatesAndSetsRemainingTime() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FocusSessionStore(defaults: defaults)
        #expect(!store.isActive)
        #expect(store.remaining() == 0)

        await store.start(minutes: 25)
        #expect(store.isActive)
        #expect(store.remaining() > 1400 && store.remaining() <= 1500)
        #expect(store.blocksPlatforms)
    }

    @Test func stopSessionDeactivates() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FocusSessionStore(defaults: defaults)
        await store.start(minutes: 10)
        #expect(store.isActive)

        store.stop()
        #expect(!store.isActive)
        #expect(store.remaining() == 0)
    }

    @Test func expiredSessionIsNotActive() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Date.now.addingTimeInterval(-100), forKey: "focusSessionEndDate")
        let store = FocusSessionStore(defaults: defaults)
        #expect(!store.isActive)
        #expect(store.remaining() == 0)
    }

    @Test func blocksPlatformsSettingPersists() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store1 = FocusSessionStore(defaults: defaults)
        store1.blocksPlatforms = false

        let store2 = FocusSessionStore(defaults: defaults)
        #expect(!store2.blocksPlatforms)
    }
}

@Suite struct UsageStoreTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuietFeedTests-Usage-\(UUID().uuidString)", isDirectory: true)

    @Test func recordPlatformSession() {
        let store = UsageStore(directory: folder)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(300) // 5 minutes

        store.begin(platformID: "youtube", at: t0)
        store.end(at: t1)

        #expect(store.records.count == 1)
        #expect(store.records.first?.platformID == "youtube")
        #expect(store.records.first?.duration == 300)

        let recorded = store.duration(platformID: "youtube", since: t0.addingTimeInterval(-60), now: t1)
        #expect(recorded == 300)
    }

    @Test func multiplePlatformsAndFiltering() {
        let store = UsageStore(directory: folder)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        store.begin(platformID: "youtube", at: t0)
        store.end(at: t0.addingTimeInterval(200))

        store.begin(platformID: "instagram", at: t0.addingTimeInterval(300))
        store.end(at: t0.addingTimeInterval(600))

        let total = store.duration(since: t0, now: t0.addingTimeInterval(1000))
        #expect(total == 500)

        let ytDuration = store.duration(platformID: "youtube", since: t0, now: t0.addingTimeInterval(1000))
        #expect(ytDuration == 200)

        let igDuration = store.duration(platformID: "instagram", since: t0, now: t0.addingTimeInterval(1000))
        #expect(igDuration == 300)
    }

    @Test func activeSessionContributesToLiveDuration() {
        let store = UsageStore(directory: folder)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let tCurrent = t0.addingTimeInterval(120)

        store.begin(platformID: "spotify", at: t0)
        let live = store.duration(platformID: "spotify", since: t0, now: tCurrent)
        #expect(live == 120)

        store.end(at: tCurrent)
        let afterEnd = store.duration(platformID: "spotify", since: t0, now: tCurrent)
        #expect(afterEnd == 120)
    }

    @Test func exportCSVFormat() {
        let store = UsageStore(directory: folder)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        store.begin(platformID: "youtube", at: t0)
        store.end(at: t0.addingTimeInterval(60))

        let csv = store.exportCSV { id in
            id == "youtube" ? "YouTube, Video" : id
        }
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "platform,started_at,ended_at,duration_seconds")
        #expect(lines[1].contains("\"YouTube, Video\""))
        #expect(lines[1].hasSuffix(",60"))
    }

    @Test func resetClearsRecordsAndDeletesFile() {
        let store = UsageStore(directory: folder)
        let t0 = Date.now
        store.begin(platformID: "youtube", at: t0)
        store.end(at: t0.addingTimeInterval(30))
        #expect(!store.records.isEmpty)

        store.reset()
        #expect(store.records.isEmpty)
        #expect(store.duration(since: t0.addingTimeInterval(-100)) == 0)
    }
}

@Suite struct OfflineAudioLibraryTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuietFeedTests-Audio-\(UUID().uuidString)", isDirectory: true)

    @Test func importAndRemoveTrack() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tempAudioFile = folder.appendingPathComponent("Sample Song.m4a")
        try Data("dummy-audio-bytes".utf8).write(to: tempAudioFile)

        let library = OfflineAudioLibrary(directory: folder)
        #expect(library.tracks.isEmpty)

        library.importAudio(from: tempAudioFile)
        #expect(library.tracks.count == 1)
        #expect(library.tracks.first?.title == "Sample Song")

        let track = try #require(library.tracks.first)
        library.remove(track)
        #expect(library.tracks.isEmpty)
    }

    @Test func resetClearsLibrary() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tempAudioFile = folder.appendingPathComponent("Track2.mp3")
        try Data("audio-bytes".utf8).write(to: tempAudioFile)

        let library = OfflineAudioLibrary(directory: folder)
        library.importAudio(from: tempAudioFile)
        #expect(library.tracks.count == 1)

        library.reset()
        #expect(library.tracks.isEmpty)
    }
}
