import Foundation
import Network
import Observation

/// Whether the device has a usable network path, so an offline page can reload by itself
/// as soon as the connection returns instead of waiting for "Try again".
@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "QuietFeed.connectivity", qos: .utility))
    }

    deinit {
        monitor.cancel()
    }
}

/// How a failed page load should be handled. Kept apart from WebKit so it can be tested.
enum LoadFailurePolicy {
    enum Outcome: Equatable {
        /// Load was cancelled by QuietFeed or WebKit itself; nothing to show.
        case ignore
        /// No connection; the page reloads when the network returns.
        case offline
        /// Likely transient (a timeout or a host that didn't answer); try again after `delay`.
        case retry(after: Duration)
        /// Show the error and wait for the person to reload.
        case fail
    }

    /// Automatic retries for transient errors before the error is shown.
    static let maxRetries = 2

    static func outcome(domain: String, code: Int, attempt: Int) -> Outcome {
        if domain == NSURLErrorDomain && code == NSURLErrorCancelled { return .ignore }
        // 102: "frame load interrupted" is what WebKit reports when a load is cancelled on purpose.
        if domain == "WebKitErrorDomain" && code == 102 { return .ignore }
        guard domain == NSURLErrorDomain else { return .fail }
        switch code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed,
             NSURLErrorInternationalRoamingOff:
            return .offline
        case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost,
             NSURLErrorDNSLookupFailed:
            guard attempt < maxRetries else { return .fail }
            // 2 s, then 6 s: long enough for a flaky connection to settle, short enough to feel automatic.
            return .retry(after: .seconds(attempt == 0 ? 2 : 6))
        default:
            return .fail
        }
    }
}
