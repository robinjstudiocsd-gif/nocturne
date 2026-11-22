import Foundation

/// Suit les lancements de l'app et détecte chaque renouvellement de la signature.
public final class RenewalTracker: @unchecked Sendable {
    private enum Key {
        static let firstLaunch = "renewal.firstLaunch"
        static let launchCount = "renewal.launchCount"
        static let lastExpiry = "renewal.lastExpiry"
        static let renewals = "renewal.dates"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var firstLaunch: Date? { defaults.object(forKey: Key.firstLaunch) as? Date }
    public var launchCount: Int { defaults.integer(forKey: Key.launchCount) }
    public var renewals: [Date] { (defaults.array(forKey: Key.renewals) as? [Date]) ?? [] }

    /// À appeler à chaque lancement. Renvoie vrai si la signature a changé depuis le lancement précédent.
    @discardableResult
    public func recordLaunch(signing: SigningStatus, now: Date = Date()) -> Bool {
        if firstLaunch == nil {
            defaults.set(now, forKey: Key.firstLaunch)
        }
        defaults.set(launchCount + 1, forKey: Key.launchCount)

        guard let expiry = signing.expirationDate else { return false }
        let previous = defaults.object(forKey: Key.lastExpiry) as? Date
        defaults.set(expiry, forKey: Key.lastExpiry)
        guard let previous, abs(previous.timeIntervalSince(expiry)) > 60 else { return false }
        defaults.set(renewals + [now], forKey: Key.renewals)
        return true
    }
}
