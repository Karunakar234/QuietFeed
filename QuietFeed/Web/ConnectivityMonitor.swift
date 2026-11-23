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
        // Path updates arrive on the monitor's queue; a stream carries them to the main actor.
        let (updates, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        monitor.pathUpdateHandler = { path in continuation.yield(path.status == .satisfied) }
        monitor.start(queue: DispatchQueue(label: "QuietFeed.connectivity", qos: .utility))
        Task { [weak self] in
            for await online in updates {
                guard let self else { return }
                if self.isOnline != online { self.isOnline = online }
            }
        }
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
        // Matched on the code alone, as before, whichever domain WebKit reports it in.
        if code == NSURLErrorCancelled { return .ignore }
        // 102: "frame load interrupted" is what WebKit reports when a load is cancelled on purpose.
        if domain == "WebKitErrorDomain" && code == 102 { return .ignore }
        switch code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed,
             NSURLErrorInternationalRoamingOff:
            return .offline
        case _ where domain != NSURLErrorDomain:
            return .fail
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
