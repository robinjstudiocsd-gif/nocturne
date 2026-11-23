import Foundation

/// Type d'un événement nocturne (étude, « Événements nocturnes »).
public enum EventKind: String, Codable, Sendable, CaseIterable {
    case snoring
    case breathing
    case cough
    case speech
    case movement
    case awakening
    case external
    case unusual

    public var title: String {
        switch self {
        case .snoring: "Ronflement"
        case .breathing: "Respiration bruyante"
        case .cough: "Toux"
        case .speech: "Paroles"
        case .movement: "Mouvement"
        case .awakening: "Réveil"
        case .external: "Bruit extérieur"
        case .unusual: "Son inhabituel"
        }
    }

    /// Titre au pluriel, pour les filtres et les totaux.
    public var pluralTitle: String {
        switch self {
        case .snoring: "Ronflements"
        case .breathing: "Respirations bruyantes"
        case .cough: "Toux"
        case .speech: "Paroles"
        case .movement: "Mouvements"
        case .awakening: "Réveils"
        case .external: "Bruits extérieurs"
        case .unusual: "Sons inhabituels"
        }
    }

    /// Les types reconnus dans le son.
    public static let sounds: [EventKind] = [.snoring, .breathing, .cough, .speech, .external, .unusual]

    /// Écart maximal entre deux détections pour qu'elles forment un seul événement.
    /// Un ronflement revient toutes les quelques secondes : ses détections se regroupent plus largement.
    public var mergeGap: TimeInterval {
        switch self {
        case .snoring: 30
        case .breathing: 20
        case .speech, .cough: 10
        case .movement, .awakening, .external, .unusual: 5
        }
    }
}

/// D'où vient le type d'un événement.
public enum EventOrigin: String, Codable, Sendable {
    /// Classé par l'app.
    case detected
    /// Confirmé par l'utilisateur.
    case confirmed
    /// Reclassé par l'utilisateur.
    case reclassified
}

/// Niveau de confiance affiché.
public enum ConfidenceLevel: String, Sendable {
    case high
    case medium
    case low

    public init(_ confidence: Double) {
        if confidence >= 0.8 {
            self = .high
        } else if confidence >= 0.5 {
            self = .medium
        } else {
            self = .low
        }
    }

    public var title: String {
        switch self {
        case .high: "élevée"
        case .medium: "moyenne"
        case .low: "faible"
        }
    }
}

/// Un événement de la nuit : il sert d'index à la réécoute et aux statistiques.
public struct NightEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var kind: EventKind
    /// Type d'origine, gardé même après une correction.
    public var detectedKind: EventKind
    public var start: Date
    public var duration: TimeInterval
    /// Confiance du classement, de 0 à 1.
    public var confidence: Double
    /// Intensité relative : écart au bruit de fond, en décibels non calibrés.
    public var intensity: Double
    public var origin: EventOrigin
    /// Vrai si l'utilisateur a indiqué « ce n'est pas moi ».
    public var isSomeoneElse: Bool
    /// Favori : le passage est protégé du nettoyage automatique.
    public var isFavorite: Bool
    /// Étiquette précise du classifieur d'Apple (« dog_bark », « door »…), si elle est connue.
    public var label: String?
    /// Extrait audio gardé autour de l'événement, s'il y en a un.
    public var clipPath: String?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        kind: EventKind,
        detectedKind: EventKind? = nil,
        start: Date,
        duration: TimeInterval,
        confidence: Double,
        intensity: Double,
        origin: EventOrigin = .detected,
        isSomeoneElse: Bool = false,
        isFavorite: Bool = false,
        label: String? = nil,
        clipPath: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.detectedKind = detectedKind ?? kind
        self.start = start
        self.duration = max(0, duration)
        self.confidence = min(1, max(0, confidence))
        self.intensity = intensity
        self.origin = origin
        self.isSomeoneElse = isSomeoneElse
        self.isFavorite = isFavorite
        self.label = label
        self.clipPath = clipPath
    }

    public var end: Date {
        start.addingTimeInterval(duration)
    }

    public var confidenceLevel: ConfidenceLevel {
        ConfidenceLevel(confidence)
    }

    /// Famille d'un bruit extérieur (circulation, chien, porte…), d'après l'étiquette.
    public var outsideNoise: OutsideNoise? {
        guard kind == .external else { return nil }
        return OutsideNoise(label: label)
    }

    /// Correction par l'utilisateur : le type d'origine reste connu.
    public func reclassified(as newKind: EventKind) -> NightEvent {
        var copy = self
        copy.kind = newKind
        copy.origin = newKind == detectedKind ? .confirmed : .reclassified
        return copy
    }
}

/// Familles de bruits extérieurs, pour l'ambiance de la chambre.
public enum OutsideNoise: String, CaseIterable, Sendable {
    case traffic
    case siren
    case transport
    case dog
    case animal
    case door
    case ringing
    case weather
    case water
    case media
    case baby
    case household
    case other

    public var title: String {
        switch self {
        case .traffic: "Circulation"
        case .siren: "Sirène"
        case .transport: "Train ou avion"
        case .dog: "Chien"
        case .animal: "Autre animal"
        case .door: "Porte"
        case .ringing: "Sonnerie"
        case .weather: "Pluie, orage ou vent"
        case .water: "Eau"
        case .media: "Musique ou télé"
        case .baby: "Bébé"
        case .household: "Bruit de la maison"
        case .other: "Autre bruit"
        }
    }

    /// Range une étiquette du classifieur d'Apple dans sa famille.
    public init(label: String?) {
        let value = (label ?? "").lowercased()
        func has(_ words: String...) -> Bool { words.contains { value.contains($0) } }
        if has("siren") {
            self = .siren
        } else if has("car", "traffic", "engine", "truck", "bus", "motorcycle", "vehicle", "horn") {
            self = .traffic
        } else if has("train", "aircraft", "airplane", "helicopter", "subway") {
            self = .transport
        } else if has("dog", "bark", "howl") {
            self = .dog
        } else if has("cat", "bird", "rooster", "crow", "owl", "insect", "cricket") {
            self = .animal
        } else if has("door", "knock") {
            self = .door
        } else if has("telephone", "bell", "alarm", "ring") {
            self = .ringing
        } else if has("rain", "thunder", "wind", "storm") {
            self = .weather
        } else if has("water", "toilet", "sink", "drip") {
            self = .water
        } else if has("music", "television", "radio", "singing") {
            self = .media
        } else if has("baby") {
            self = .baby
        } else if has("footsteps", "dishes", "glass", "keys", "drawer", "chair") {
            self = .household
        } else {
            self = .other
        }
    }
}

/// Accès aux événements des nuits.
public protocol NightEventRepository: Sendable {
    func events(sessionID: UUID) async throws -> [NightEvent]
    func events(in interval: DateInterval?) async throws -> [NightEvent]
    func save(_ events: [NightEvent]) async throws
    func delete(id: UUID) async throws
    func deleteAll(sessionID: UUID) async throws
}

/// Version en mémoire, pour les tests et les aperçus.
public actor InMemoryNightEventRepository: NightEventRepository {
    private var storage: [UUID: NightEvent] = [:]

    public init(_ events: [NightEvent] = []) {
        for event in events {
            storage[event.id] = event
        }
    }

    public func events(sessionID: UUID) async throws -> [NightEvent] {
        storage.values.filter { $0.sessionID == sessionID }.sorted { $0.start < $1.start }
    }

    public func events(in interval: DateInterval?) async throws -> [NightEvent] {
        storage.values
            .filter { event in interval.map { $0.contains(event.start) } ?? true }
            .sorted { $0.start < $1.start }
    }

    public func save(_ events: [NightEvent]) async throws {
        for event in events {
            storage[event.id] = event
        }
    }

    public func delete(id: UUID) async throws {
        storage[id] = nil
    }

    public func deleteAll(sessionID: UUID) async throws {
        storage = storage.filter { $0.value.sessionID != sessionID }
    }
}
