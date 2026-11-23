import Foundation
import SleepDomain

/// Textes des modes d'écoute et des coupures.
enum NightText {
    static func modeTitle(_ mode: RecordingMode) -> String {
        switch mode {
        case .continuous: "Continu"
        case .events: "Événements"
        case .economy: "Économie"
        case .off: "Coupé"
        }
    }

    /// Sous-titre de la ligne « Mode d'écoute ».
    static func modeSubtitle(_ mode: RecordingMode, retention: Int) -> String {
        switch mode {
        case .continuous: "Nuit entière, gardée \(nights(retention))"
        case .events: "Chaque bruit, 5 s avant et après"
        case .economy: "30 extraits courts au plus"
        case .off: "Horaires seulement, sans micro"
        }
    }

    /// Explication dans la liste des modes.
    static func modeDescription(_ mode: RecordingMode, retention: Int) -> String {
        switch mode {
        case .continuous:
            "Toute la nuit, en tranches de 5 min, avec chaque bruit repéré. L’audio est gardé \(nights(retention))."
        case .events:
            "Seulement les bruits, avec 5 s avant et après. Prend peu de place."
        case .economy:
            "30 extraits de 15 s au plus, en qualité réduite. Le plus léger."
        case .off:
            "Le micro reste coupé : seuls les horaires de la nuit sont notés."
        }
    }

    /// « mode continu », pour l'écran de nuit.
    static func modeShort(_ mode: RecordingMode) -> String {
        switch mode {
        case .continuous: "mode continu"
        case .events: "mode événements"
        case .economy: "mode économie"
        case .off: "micro coupé"
        }
    }

    /// « Un appel a coupé l'écoute à 02:31. »
    static func cutSentence(_ cause: RecordingGap.Cause, at clock: String) -> String {
        switch cause {
        case .phoneCall: "Un appel a coupé l’écoute à \(clock)."
        case .siri: "Siri a coupé l’écoute à \(clock)."
        case .otherAudio: "Une autre app audio a coupé l’écoute à \(clock)."
        case .systemStop: "iOS a arrêté l’écoute à \(clock)."
        case .microphoneUnavailable: "Le micro n’est plus disponible depuis \(clock)."
        case .lowBattery: "La batterie faible a arrêté l’écoute à \(clock)."
        case .appTerminated: "L’app a été fermée à \(clock)."
        case .unknown: "L’écoute s’est coupée à \(clock)."
        }
    }

    static func nights(_ count: Int) -> String {
        count > 1 ? "\(count) nuits" : "\(count) nuit"
    }
}
