import Foundation
import Observation

/// The platform that's open over the tabs, and whether it's shrunk into the mini-player.
/// One platform is open at a time; opening another one replaces it.
@MainActor
@Observable
final class PlayerSession {
    private enum RecoveryKey {
        static let platformID = "recoverablePlatformID"
        static let savedAt = "recoverablePlatformSavedAt"
    }

    private(set) var platform: Platform?
    /// The page to open instead of the platform's home, such as a recommended search.
    private(set) var startURL: URL?
    private(set) var isMinimized = false
    private(set) var isVideoFullscreen = false
    private(set) var recoveryPlatformID: String?
    @ObservationIgnored private let defaults: UserDefaults

    /// One platform's home, loaded in the background before it's opened (the one the person
    /// opened last), so opening it shows the page straight away instead of a loading screen.
    @ObservationIgnored private var preloaded: WebModel?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedAt = defaults.object(forKey: RecoveryKey.savedAt) as? Date
        if let savedAt, Date.now.timeIntervalSince(savedAt) < 24 * 60 * 60 {
            recoveryPlatformID = defaults.string(forKey: RecoveryKey.platformID)
        } else {
            defaults.removeObject(forKey: RecoveryKey.platformID)
            defaults.removeObject(forKey: RecoveryKey.savedAt)
        }
    }

    /// Changes whenever a different page is opened, so the screen builds a fresh web view for it.
    var openID: String { "\(platform?.id ?? "")|\(startURL?.absoluteString ?? "")" }

    var preloadedPlatformID: String? { preloaded?.platform.id }

    /// Keeps `model` loading in the background, replacing any earlier one.
    func preload(_ model: WebModel) {
        if preloaded !== model { preloaded?.shutdown() }
        preloaded = model
    }

    /// Releases the background page if it belongs to `platformID`, so its website data is no
    /// longer in use (WebKit won't delete data a live page holds).
    func discardPreloaded(platformID: String) {
        guard preloaded?.platform.id == platformID else { return }
        preloaded?.shutdown()
        preloaded = nil
    }

    /// Whether `model` is the page kept in the background, so closing mustn't shut it down.
    func isPreloaded(_ model: WebModel) -> Bool { preloaded === model }

    /// The preloaded page, if it's this platform's home in this account. Handed over once.
    func takePreloaded(platformID: String, startURL: URL?, dataStoreID: UUID) -> WebModel? {
        guard startURL == nil, let model = preloaded, model.platform.id == platformID,
              model.dataStoreID == dataStoreID else { return nil }
        preloaded = nil
        model.unpark()
        return model
    }

    /// Opens a platform full screen, at its home or at `url`. Opening the platform that's
    /// already in the mini-player, without a new page, expands it instead of reloading.
    func open(_ platform: Platform, at url: URL? = nil) {
        if self.platform?.id == platform.id && url == nil {
            isMinimized = false
            return
        }
        self.platform = platform
        startURL = url
        isMinimized = false
        recoveryPlatformID = nil
        defaults.set(platform.id, forKey: RecoveryKey.platformID)
        defaults.set(Date.now, forKey: RecoveryKey.savedAt)
        // Only one page in the background at a time: a different platform frees the preloaded one.
        if preloaded?.platform.id != platform.id {
            preloaded?.shutdown()
            preloaded = nil
        }
    }

    func minimize() {
        guard platform != nil else { return }
        isMinimized = true
    }

    func expand() {
        isMinimized = false
    }

    func setVideoFullscreen(_ active: Bool) {
        isVideoFullscreen = active
    }

    /// Closes the platform. Its web view is released, so playback stops.
    func close() {
        platform = nil
        startURL = nil
        isMinimized = false
        isVideoFullscreen = false
        discardRecovery()
    }

    func discardRecovery() {
        recoveryPlatformID = nil
        defaults.removeObject(forKey: RecoveryKey.platformID)
        defaults.removeObject(forKey: RecoveryKey.savedAt)
    }
}
