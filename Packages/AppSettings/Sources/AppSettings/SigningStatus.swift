import Foundation

/// Date d'expiration de la signature, lue dans le profil que Sideloadly place dans l'app.
public struct SigningStatus: Sendable, Equatable {
    public let expirationDate: Date?

    public init(expirationDate: Date?) {
        self.expirationDate = expirationDate
    }

    /// Lit le profil embarqué dans l'app (`embedded.mobileprovision`).
    public static func read(bundleURL: URL) -> SigningStatus {
        let url = bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: url) else { return SigningStatus(expirationDate: nil) }
        return SigningStatus(expirationDate: expiration(inProfile: data))
    }

    /// Extrait la date d'expiration du plist contenu dans un profil signé.
    public static func expiration(inProfile data: Data) -> Date? {
        guard
            let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(of: Data("</plist>".utf8), options: [], in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard
            let object = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
            let plist = object as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    /// Jours pleins restants avant l'expiration, ou nil si la date est inconnue.
    public func daysRemaining(now: Date = Date()) -> Int? {
        guard let expirationDate else { return nil }
        return Int(floor(expirationDate.timeIntervalSince(now) / 86_400))
    }

    /// Vrai quand il reste moins de deux jours : il faut renouveler avec Sideloadly.
    public func needsRenewal(now: Date = Date()) -> Bool {
        guard let expirationDate else { return false }
        return expirationDate.timeIntervalSince(now) < 2 * 86_400
    }
}
