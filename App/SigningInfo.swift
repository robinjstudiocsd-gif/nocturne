import Foundation

/// Lit la date d'expiration de la signature dans le profil que Sideloadly place dans l'app.
enum SigningInfo {
    static func expirationDate() -> Date? {
        guard
            let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url),
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
}

/// Suit les lancements et détecte chaque renouvellement de la signature (test n° 7).
final class LaunchTracker {
    private let defaults = UserDefaults.standard

    private(set) var firstLaunch: Date
    private(set) var launchCount: Int
    private(set) var renewals: [Date]
    let expiry: Date?

    init() {
        expiry = SigningInfo.expirationDate()
        if let first = defaults.object(forKey: "lab.firstLaunch") as? Date {
            firstLaunch = first
        } else {
            firstLaunch = Date()
            defaults.set(firstLaunch, forKey: "lab.firstLaunch")
        }
        launchCount = defaults.integer(forKey: "lab.launchCount") + 1
        defaults.set(launchCount, forKey: "lab.launchCount")
        renewals = (defaults.array(forKey: "lab.renewals") as? [Date]) ?? []

        let previous = defaults.object(forKey: "lab.lastExpiry") as? Date
        if let expiry {
            if let previous, abs(previous.timeIntervalSince(expiry)) > 60 {
                renewals.append(Date())
                defaults.set(renewals, forKey: "lab.renewals")
                EventLog.shared.add("Renouvellement détecté : la signature expirait le \(Format.dateTime(previous)), elle expire maintenant le \(Format.dateTime(expiry)). Données conservées.")
            }
            defaults.set(expiry, forKey: "lab.lastExpiry")
        }
        EventLog.shared.add("Lancement n° \(launchCount) · signature \(expiry.map { "valide jusqu’au \(Format.dateTime($0))" } ?? "inconnue")")
    }
}
