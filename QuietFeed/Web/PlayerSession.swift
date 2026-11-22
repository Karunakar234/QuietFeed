import Foundation
import Observation

/// The platform that's open over the tabs, and whether it's shrunk into the mini-player.
/// One platform is open at a time; opening another one replaces it.
@MainActor
@Observable
final class PlayerSession {
    private(set) var platform: Platform?
    /// The page to open instead of the platform's home, such as a recommended search.
    private(set) var startURL: URL?
    private(set) var isMinimized = false
    private(set) var isVideoFullscreen = false

    /// One platform's home, loaded in the background before it's opened (the one the person
    /// opened last), so opening it shows the page straight away instead of a loading screen.
    @ObservationIgnored private var preloaded: WebModel?

    /// Changes whenever a different page is opened, so the screen builds a fresh web view for it.
    var openID: String { "\(platform?.id ?? "")|\(startURL?.absoluteString ?? "")" }

    var preloadedPlatformID: String? { preloaded?.platform.id }

    /// Keeps `model` loading in the background, replacing any earlier one.
    func preload(_ model: WebModel) {
        if preloaded !== model { preloaded?.shutdown() }
        preloaded = model
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
    }
}
