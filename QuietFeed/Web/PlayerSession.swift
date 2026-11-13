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

    /// Changes whenever a different page is opened, so the screen builds a fresh web view for it.
    var openID: String { "\(platform?.id ?? "")|\(startURL?.absoluteString ?? "")" }

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
