import Foundation
import SleepDomain

/// Bruit de fond de la pièce : le niveau que la chambre atteint 20 % du temps sur les 5 dernières minutes.
/// Il suit lentement les changements (ventilateur allumé, fenêtre ouverte) sans être tiré par les pics.
public struct NoiseFloorTracker: Sendable {
    public static let window = 300
    private var levels: [Float] = []
    private var next = 0
    private var cached: Float?
    private var sinceUpdate = 0

    public init() {}

    /// Ajoute le niveau d'une seconde et renvoie le bruit de fond courant.
    public mutating func add(_ level: Float) -> Float {
        if levels.count < Self.window {
            levels.append(level)
        } else {
            levels[next] = level
            next = (next + 1) % Self.window
        }
        sinceUpdate += 1
        if cached == nil || sinceUpdate >= 10 || levels.count < 30 {
            let sorted = levels.sorted()
            cached = sorted[min(sorted.count - 1, sorted.count / 5)]
            sinceUpdate = 0
        }
        return cached ?? level
    }

    public var floor: Float? {
        cached
    }
}

/// Quand faire écouter le passage au classifieur : au-dessus du bruit de fond d'un seuil réglable,
/// et une seconde par minute pour capter aussi les sons faibles.
public struct DetectionTrigger: Sendable {
    /// Seuil par défaut au-dessus du bruit de fond, en décibels.
    public static let defaultThreshold: Float = 10

    public var threshold: Float
    /// Secondes d'écoute gardées après le dernier dépassement.
    public var holdSeconds: Int
    private var activeUntil = -1
    private var lastSample = -60

    public init(threshold: Float = DetectionTrigger.defaultThreshold, holdSeconds: Int = 3) {
        self.threshold = threshold
        self.holdSeconds = holdSeconds
    }

    /// Vrai si la seconde `second` doit être analysée.
    public mutating func shouldAnalyze(second: Int, level: Float, floor: Float) -> Bool {
        if level >= floor + threshold {
            activeUntil = second + holdSeconds
        }
        if second <= activeUntil {
            lastSample = second
            return true
        }
        if second - lastSample >= 60 {
            lastSample = second
            return true
        }
        return false
    }
}

/// Étiquettes du classifieur de sons d'Apple regroupées en types d'événements.
/// Les étiquettes inconnues donnent un « son inhabituel » si le son dépasse nettement le bruit de fond.
public enum SoundLabelMap {
    static let snoring: Set<String> = ["snoring"]
    static let breathing: Set<String> = ["breathing", "gasp", "sigh", "wheeze", "pant"]
    static let cough: Set<String> = ["cough", "sneeze", "throat_clearing"]
    static let speech: Set<String> = ["speech", "whispering", "shout", "yell", "laughter", "giggling", "crying_sobbing", "singing", "humming"]
    static let external: Set<String> = [
        "dog", "dog_bark", "dog_bow_wow", "cat", "cat_meow", "bird", "rooster_crow",
        "door", "door_slam", "knock", "door_bell", "telephone", "telephone_bell_ringing", "alarm_clock",
        "car_horn", "car_passing_by", "siren", "police_siren", "ambulance_siren", "fire_engine_siren",
        "engine", "motorcycle", "truck", "bus", "train", "aircraft", "airplane", "helicopter",
        "traffic", "rain", "thunder", "wind", "water", "toilet_flush", "music", "television", "radio",
        "baby_crying", "footsteps", "glass_breaking", "dishes_pots_and_pans", "keys_jangling"
    ]
    /// Étiquettes à ignorer : rien d'utile à retenir.
    static let ignored: Set<String> = ["silence", "noise", "white_noise", "pink_noise", "hum", "fan", "air_conditioner", "mechanical_fan", "tick", "tick_tock"]

    /// Confiance minimale pour retenir une étiquette.
    public static let minimumConfidence = 0.5

    public static func kind(for identifier: String) -> EventKind? {
        let label = identifier.lowercased()
        if ignored.contains(label) { return nil }
        if snoring.contains(label) { return .snoring }
        if breathing.contains(label) { return .breathing }
        if cough.contains(label) { return .cough }
        if speech.contains(label) { return .speech }
        if external.contains(label) { return .external }
        return .unusual
    }
}

/// Une seconde classée par l'app.
public struct SoundDetection: Equatable, Sendable {
    public var time: Date
    public var kind: EventKind
    public var confidence: Double
    /// Écart au bruit de fond, en décibels.
    public var intensity: Double
    public var duration: TimeInterval

    public init(time: Date, kind: EventKind, confidence: Double, intensity: Double, duration: TimeInterval = 1) {
        self.time = time
        self.kind = kind
        self.confidence = confidence
        self.intensity = intensity
        self.duration = duration
    }
}

/// Regroupe les détections proches du même type en événements, avec début, durée, intensité et confiance.
public struct EventAggregator: Sendable {
    public let sessionID: UUID
    private var open: [EventKind: NightEvent] = [:]

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    /// Ajoute une détection ; renvoie les événements refermés (trop loin de cette détection).
    public mutating func add(_ detection: SoundDetection) -> [NightEvent] {
        var closed = close(before: detection.time)
        if var current = open[detection.kind], detection.time.timeIntervalSince(current.end) <= detection.kind.mergeGap {
            let end = max(current.end, detection.time.addingTimeInterval(detection.duration))
            current.duration = end.timeIntervalSince(current.start)
            current.confidence = max(current.confidence, detection.confidence)
            current.intensity = max(current.intensity, detection.intensity)
            open[detection.kind] = current
        } else {
            if let previous = open[detection.kind] {
                closed.append(previous)
            }
            open[detection.kind] = NightEvent(
                sessionID: sessionID,
                kind: detection.kind,
                start: detection.time,
                duration: detection.duration,
                confidence: detection.confidence,
                intensity: detection.intensity
            )
        }
        return closed.sorted { $0.start < $1.start }
    }

    /// Referme les événements dont la dernière détection est trop ancienne.
    public mutating func close(before time: Date) -> [NightEvent] {
        var closed: [NightEvent] = []
        for (kind, event) in open where time.timeIntervalSince(event.end) > kind.mergeGap {
            closed.append(event)
            open[kind] = nil
        }
        return closed.sorted { $0.start < $1.start }
    }

    /// Fin de la nuit : tout ce qui reste ouvert est refermé.
    public mutating func flush() -> [NightEvent] {
        let remaining = open.values.sorted { $0.start < $1.start }
        open = [:]
        return remaining
    }
}
