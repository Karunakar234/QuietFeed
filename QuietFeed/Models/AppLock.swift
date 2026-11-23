import Foundation
import LocalAuthentication
import Observation

/// Optional app lock: Face ID, Touch ID or the device passcode before QuietFeed shows anything,
/// at launch and after it's been in the background. Off by default.
///
/// Only a yes/no comes back from the system; QuietFeed never sees biometric data.
@MainActor
@Observable
final class AppLock {
    /// Asks the system to authenticate the device owner. Swappable for tests.
    typealias Authenticator = (_ reason: String) async -> Result<Void, AuthError>

    enum AuthError: Error, Equatable {
        /// No passcode is set, so there's nothing to unlock with.
        case unavailable
        case cancelled
        case failed
    }

    private static let enabledKey = "appLockEnabled"

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var lastError: AuthError?

    /// Whether the unlock prompt already appeared for the current lock, so cancelling it
    /// doesn't bring it straight back (the prompt itself makes the app inactive and active again).
    @ObservationIgnored private var didAutoPrompt = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let authenticate: Authenticator

    init(defaults: UserDefaults = .standard, authenticate: @escaping Authenticator = AppLock.systemAuthenticate) {
        self.defaults = defaults
        self.authenticate = authenticate
        let enabled = defaults.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    /// Turning the lock on needs one successful unlock first, which proves the person can get
    /// back in. Turning it off needs one too, so someone holding an unlocked phone can't.
    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isEnabled else { return true }
        let reason = enabled ? "Turn on the QuietFeed lock" : "Turn off the QuietFeed lock"
        guard await runAuthentication(reason: reason) else { return false }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        isLocked = false
        return true
    }

    /// Called when the app goes to the background.
    func lock() {
        guard isEnabled else { return }
        isLocked = true
        didAutoPrompt = false
    }

    /// Called when the app becomes active: shows the prompt once per lock.
    func promptIfNeeded() async {
        guard isLocked, !didAutoPrompt else { return }
        didAutoPrompt = true
        await unlock()
    }

    func unlock() async {
        guard isLocked else { return }
        if await runAuthentication(reason: "Unlock QuietFeed") { isLocked = false }
    }

    /// Used by "Delete my data", which returns the app to its first-launch state.
    func reset() {
        isEnabled = false
        isLocked = false
        defaults.removeObject(forKey: Self.enabledKey)
    }

    private func runAuthentication(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        switch await authenticate(reason) {
        case .success:
            lastError = nil
            return true
        case .failure(let error):
            lastError = error
            return false
        }
    }

    /// `.deviceOwnerAuthentication` falls back to the passcode, so a failed Face ID never locks
    /// the person out of their own app.
    nonisolated static func systemAuthenticate(reason: String) async -> Result<Void, AuthError> {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .failure(.unavailable)
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
                ? .success(()) : .failure(.failed)
        } catch let laError as LAError where [.userCancel, .systemCancel, .appCancel].contains(laError.code) {
            return .failure(.cancelled)
        } catch {
            return .failure(.failed)
        }
    }
}
