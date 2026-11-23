import Foundation

/// État d'une autorisation d'iOS.
public enum PermissionState: String, Sendable, Equatable {
    case granted
    case denied
    case undetermined
}

/// Mesures prises sur l'iPhone juste avant la nuit.
public struct PreflightReadings: Equatable, Sendable {
    /// Niveau de la batterie, de 0 à 1, ou nil s'il est inconnu.
    public var batteryLevel: Double?
    /// Vrai si l'iPhone est branché (en charge ou plein).
    public var isPluggedIn: Bool
    /// Volume des médias, de 0 à 1 : la sonnerie jouée par l'app le suit.
    public var volume: Double?
    public var freeBytes: Int64?
    public var microphone: PermissionState
    public var notifications: PermissionState
    public var signatureExpiry: Date?

    public init(
        batteryLevel: Double? = nil,
        isPluggedIn: Bool = false,
        volume: Double? = nil,
        freeBytes: Int64? = nil,
        microphone: PermissionState = .undetermined,
        notifications: PermissionState = .undetermined,
        signatureExpiry: Date? = nil
    ) {
        self.batteryLevel = batteryLevel
        self.isPluggedIn = isPluggedIn
        self.volume = volume
        self.freeBytes = freeBytes
        self.microphone = microphone
        self.notifications = notifications
        self.signatureExpiry = signatureExpiry
    }
}

/// Ce que l'utilisateur peut faire depuis une vérification.
public enum PreflightAction: Equatable, Sendable {
    case requestMicrophone
    case requestNotifications
    case openSettings

    public var title: String {
        switch self {
        case .requestMicrophone, .requestNotifications: "Autoriser"
        case .openSettings: "Ouvrir les Réglages"
        }
    }
}

/// Une ligne de la rubrique « Vérifications ».
public struct PreflightItem: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case battery
        case volume
        case storage
        case permissions
        case signature
    }

    public enum Status: Sendable, Equatable {
        case ready
        case warning
        case unknown
    }

    public var kind: Kind
    public var status: Status
    public var title: String
    public var value: String
    public var detail: String?
    public var action: PreflightAction?

    public init(kind: Kind, status: Status, title: String, value: String, detail: String? = nil, action: PreflightAction? = nil) {
        self.kind = kind
        self.status = status
        self.title = title
        self.value = value
        self.detail = detail
        self.action = action
    }

    public var id: Kind { kind }
}

/// Fournit les mesures et les demandes d'autorisation, côté iPhone.
public protocol PreflightProvider: Sendable {
    func readings() async -> PreflightReadings
    func requestMicrophone() async -> Bool
    func requestNotifications() async -> Bool
}

/// Les vérifications de « Préparer ma nuit » : batterie, volume, espace libre, autorisations, signature.
public enum Preflight {
    /// En dessous, la sonnerie jouée par l'app risque de ne pas réveiller.
    public static let minimumVolume = 0.5
    /// Seuil de batterie faible quand l'iPhone n'est pas branché.
    public static let lowBattery = 0.2
    /// Place gardée en plus de l'estimation de la nuit.
    public static let storageMargin: Int64 = 500_000_000
    /// Renouveler la signature quand il reste moins de deux jours.
    public static let renewalMargin: TimeInterval = 2 * 86_400

    /// Taille estimée d'une nuit de 9 heures, audio et séries comprises.
    public static func estimatedBytes(mode: RecordingMode, quality: AudioQuality, hours: Double = 9) -> Int64 {
        let series: Int64 = 1_000_000
        switch mode {
        case .continuous:
            return Int64(Double(quality.bitRate) / 8 * hours * 3_600) + series
        case .events:
            return 30_000_000 + series
        case .economy:
            return 10_000_000 + series
        case .off:
            return 0
        }
    }

    public static func evaluate(
        _ readings: PreflightReadings,
        kind: SessionKind,
        mode: RecordingMode,
        quality: AudioQuality,
        alarm: NightAlarm?,
        now: Date,
        format: SleepFormat = SleepFormat()
    ) -> [PreflightItem] {
        [
            battery(readings, kind: kind, mode: mode),
            volume(readings, alarm: alarm),
            storage(readings, mode: mode, quality: quality, format: format),
            permissions(readings, mode: mode),
            signature(readings, kind: kind, alarm: alarm, now: now, format: format)
        ]
    }

    /// « 4 sur 5 prêtes »
    public static func summary(_ items: [PreflightItem]) -> String {
        let ready = items.filter { $0.status == .ready }.count
        return "\(ready) sur \(items.count) prête\(ready > 1 ? "s" : "")"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded())) %"
    }

    static func battery(_ readings: PreflightReadings, kind: SessionKind, mode: RecordingMode) -> PreflightItem {
        let title = "Batterie"
        guard let level = readings.batteryLevel else {
            return PreflightItem(kind: .battery, status: .unknown, title: title, value: "inconnue")
        }
        if readings.isPluggedIn {
            return PreflightItem(kind: .battery, status: .ready, title: title, value: percent(level), detail: "Branchée")
        }
        // Une nuit d'écoute complète se passe sur secteur ; une sieste ou une nuit sans micro tient sur batterie.
        if kind == .night && mode != .off {
            return PreflightItem(kind: .battery, status: .warning, title: title, value: percent(level), detail: "Branche ton iPhone pour la nuit")
        }
        if level < lowBattery {
            return PreflightItem(kind: .battery, status: .warning, title: title, value: percent(level), detail: "Batterie faible : branche ton iPhone")
        }
        return PreflightItem(kind: .battery, status: .ready, title: title, value: percent(level))
    }

    static func volume(_ readings: PreflightReadings, alarm: NightAlarm?) -> PreflightItem {
        let title = "Volume de l’alarme"
        guard let volume = readings.volume else {
            return PreflightItem(kind: .volume, status: .unknown, title: title, value: "inconnu")
        }
        guard alarm != nil else {
            return PreflightItem(kind: .volume, status: .ready, title: title, value: percent(volume), detail: "Aucun réveil prévu")
        }
        if volume < minimumVolume {
            return PreflightItem(kind: .volume, status: .warning, title: title, value: percent(volume), detail: "Monte le volume : la sonnerie le suit")
        }
        return PreflightItem(kind: .volume, status: .ready, title: title, value: percent(volume))
    }

    static func storage(_ readings: PreflightReadings, mode: RecordingMode, quality: AudioQuality, format: SleepFormat) -> PreflightItem {
        let title = "Espace libre"
        guard let free = readings.freeBytes else {
            return PreflightItem(kind: .storage, status: .unknown, title: title, value: "inconnu")
        }
        let needed = estimatedBytes(mode: mode, quality: quality)
        if mode != .off && free < needed + storageMargin {
            return PreflightItem(
                kind: .storage,
                status: .warning,
                title: title,
                value: format.bytes(free),
                detail: "Libère de la place : une nuit prend environ \(format.bytes(needed))"
            )
        }
        return PreflightItem(kind: .storage, status: .ready, title: title, value: format.bytes(free))
    }

    static func permissions(_ readings: PreflightReadings, mode: RecordingMode) -> PreflightItem {
        let title = "Micro et notifications"
        if mode != .off {
            switch readings.microphone {
            case .denied:
                return PreflightItem(kind: .permissions, status: .warning, title: title, value: "Micro refusé", detail: "Autorise le micro dans les Réglages, ou choisis le mode Coupé", action: .openSettings)
            case .undetermined:
                return PreflightItem(kind: .permissions, status: .warning, title: title, value: "À autoriser", detail: "Le micro sert à écouter la nuit", action: .requestMicrophone)
            case .granted:
                break
            }
        }
        switch readings.notifications {
        case .denied:
            return PreflightItem(kind: .permissions, status: .warning, title: title, value: "Refusées", detail: "Sans notifications, pas de réveil de secours", action: .openSettings)
        case .undetermined:
            return PreflightItem(kind: .permissions, status: .warning, title: title, value: "À autoriser", detail: "Les notifications servent au réveil de secours", action: .requestNotifications)
        case .granted:
            return PreflightItem(kind: .permissions, status: .ready, title: title, value: "Autorisés")
        }
    }

    static func signature(_ readings: PreflightReadings, kind: SessionKind, alarm: NightAlarm?, now: Date, format: SleepFormat) -> PreflightItem {
        let title = "Signature de l’app"
        guard let expiry = readings.signatureExpiry else {
            return PreflightItem(kind: .signature, status: .unknown, title: title, value: "date inconnue")
        }
        let value = "jusqu’au \(format.weekdayAndDay(expiry))"
        let end = alarm?.date ?? now.addingTimeInterval(kind == .night ? 12 * 3_600 : 2 * 3_600)
        if expiry <= end {
            return PreflightItem(kind: .signature, status: .warning, title: title, value: value, detail: "Elle expire avant ton réveil : renouvelle l’app avec Sideloadly")
        }
        if expiry.timeIntervalSince(now) < renewalMargin {
            return PreflightItem(kind: .signature, status: .warning, title: title, value: value, detail: "Renouvelle bientôt l’app avec Sideloadly")
        }
        return PreflightItem(kind: .signature, status: .ready, title: title, value: value)
    }
}
