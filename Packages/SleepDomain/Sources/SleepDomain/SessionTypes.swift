import Foundation

/// Type de session : une nuit ou une sieste.
public enum SessionKind: String, Codable, Sendable, CaseIterable {
    case night
    case nap
}

/// État d'une session.
public enum SessionState: String, Codable, Sendable, CaseIterable {
    case running
    case finished
    case interrupted
    case imported
    case manual
}

/// Provenance d'une valeur : chaque donnée garde sa source.
public enum DataSource: String, Codable, Sendable, CaseIterable {
    case watch
    case microphone
    case motion
    case manual
}

/// Mode d'écoute de la nuit (étude, « Enregistrement audio »).
public enum RecordingMode: String, Codable, Sendable, CaseIterable {
    /// Toute la nuit, en tranches de 5 min, plus l'index des événements. Mode par défaut.
    case continuous
    /// Chaque événement, avec 5 s avant et après.
    case events
    /// 30 extraits de 15 s au plus, qualité réduite.
    case economy
    /// Micro coupé.
    case off
}

/// Les quatre horaires d'une nuit.
public struct SessionTimes: Hashable, Codable, Sendable {
    public var bedtime: Date?
    public var sleepOnset: Date?
    public var wake: Date?
    public var getUp: Date?

    public init(bedtime: Date? = nil, sleepOnset: Date? = nil, wake: Date? = nil, getUp: Date? = nil) {
        self.bedtime = bedtime
        self.sleepOnset = sleepOnset
        self.wake = wake
        self.getUp = getUp
    }

    /// Les valeurs présentes ici remplacent celles de `base` ; les autres viennent de `base`.
    public func overriding(_ base: SessionTimes) -> SessionTimes {
        SessionTimes(
            bedtime: bedtime ?? base.bedtime,
            sleepOnset: sleepOnset ?? base.sleepOnset,
            wake: wake ?? base.wake,
            getUp: getUp ?? base.getUp
        )
    }

    /// Les horaires présents, dans l'ordre coucher, endormissement, réveil, lever.
    var ordered: [Date] {
        [bedtime, sleepOnset, wake, getUp].compactMap { $0 }
    }
}

/// Ressenti au réveil, de 1 à 5. L'humeur ou l'énergie peut rester vide.
public struct WakeFeeling: Hashable, Codable, Sendable {
    public var mood: Int?
    public var energy: Int?

    public init(mood: Int?, energy: Int?) {
        self.mood = mood.map { min(5, max(1, $0)) }
        self.energy = energy.map { min(5, max(1, $0)) }
    }

    /// Vrai si rien n'a été choisi.
    public var isEmpty: Bool {
        mood == nil && energy == nil
    }
}

/// Problème détecté dans les horaires d'une session.
public enum SessionIssue: Hashable, Sendable {
    case timesOutOfOrder
    case longerThanADay
}
