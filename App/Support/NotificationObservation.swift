import Foundation

/// Owns an immutable observer token and unregisters it when its owner goes away.
/// NotificationCenter's registration and removal APIs are thread-safe.
final class NotificationObservation: @unchecked Sendable {
    private let token: NSObjectProtocol
    private let center: NotificationCenter

    init(token: NSObjectProtocol, center: NotificationCenter = .default) {
        self.token = token
        self.center = center
    }

    deinit {
        center.removeObserver(token)
    }
}
