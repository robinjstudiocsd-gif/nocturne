#if os(iOS)
import Foundation
import UIKit

/// Verrouillage ou déverrouillage de l'iPhone.
enum UnlockEvent: Sendable {
    case locked
    case unlocked
}

/// Surveille le verrouillage de l'iPhone pendant la nuit. iOS ne le signale que si un code est réglé.
@MainActor
final class UnlockMonitor {
    private var tokens: [NSObjectProtocol] = []

    func start(handler: @escaping @MainActor @Sendable (UnlockEvent) -> Void) {
        stop()
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                handler(.locked)
            }
        })
        tokens.append(center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                handler(.unlocked)
            }
        })
    }

    func stop() {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens.removeAll()
    }
}
#endif
