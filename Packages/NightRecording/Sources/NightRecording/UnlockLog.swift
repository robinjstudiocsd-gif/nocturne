import Foundation

/// Moments où l'iPhone était déverrouillé pendant la nuit (étude : « chaque usage du téléphone marque un éveil probable »).
/// Gardé dans le dossier de la nuit pour pouvoir refaire l'analyse plus tard.
public struct UnlockLog: Codable, Equatable, Sendable {
    public static let fileName = "deverrouillages.json"
    public static let currentVersion = 1

    public var version: Int
    public var periods: [DateInterval]
    /// Vrai dès qu'iOS a signalé un verrouillage. Sans code, iOS ne le signale jamais :
    /// la nuit entière paraîtrait alors déverrouillée, donc rien n'est retenu.
    public var sawLock: Bool
    /// Début du déverrouillage en cours, s'il y en a un.
    public var unlockedSince: Date?

    public init() {
        version = Self.currentVersion
        periods = []
        sawLock = false
        unlockedSince = nil
    }

    public mutating func unlocked(at date: Date) {
        if unlockedSince == nil {
            unlockedSince = date
        }
    }

    public mutating func locked(at date: Date) {
        sawLock = true
        close(at: date)
    }

    /// Fin de la nuit : le déverrouillage en cours s'arrête là.
    public mutating func finish(at date: Date) {
        close(at: date)
    }

    /// Périodes utiles à l'analyse.
    public var usablePeriods: [DateInterval] {
        sawLock ? periods : []
    }

    private mutating func close(at date: Date) {
        if let since = unlockedSince, date > since {
            periods.append(DateInterval(start: since, end: date))
        }
        unlockedSince = nil
    }

    public static func read(from folder: URL) -> UnlockLog? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(UnlockLog.self, from: data)
    }

    /// Écrit le fichier. Il reste lisible écran verrouillé, comme la base, pour être mis à jour toute la nuit.
    public func write(to folder: URL) throws {
        let data = try JSONEncoder().encode(self)
        let url = folder.appendingPathComponent(Self.fileName)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
