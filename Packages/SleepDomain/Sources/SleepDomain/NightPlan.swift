import Foundation

/// Éclairage de l'écran de nuit.
public enum NightLighting: String, CaseIterable, Sendable {
    case dark
    case red
}

/// Réveil prévu pour une session : l'heure limite et, si choisi, le début du réveil intelligent.
public struct NightAlarm: Codable, Hashable, Sendable {
    public var date: Date
    public var smartWindowStart: Date?

    public init(date: Date, smartWindowStart: Date? = nil) {
        self.date = date
        self.smartWindowStart = smartWindowStart
    }
}

/// Ce qui se règle sur « Préparer ma nuit » avant de commencer.
public struct NightPlan: Equatable, Sendable {
    /// Durées de sieste proposées, en minutes.
    public static let napDurations = [10, 15, 20, 25, 30, 45, 60, 90]

    public var kind: SessionKind
    public var mode: RecordingMode
    public var alarmEnabled: Bool
    public var alarmHour: Int {
        didSet { alarmHour = min(23, max(0, alarmHour)) }
    }
    public var alarmMinute: Int {
        didSet { alarmMinute = min(59, max(0, alarmMinute)) }
    }
    public var smartWake: Bool
    /// Fenêtre du réveil intelligent avant l'heure limite, en minutes.
    public var smartWindowMinutes: Int
    public var napMinutes: Int {
        didSet { napMinutes = min(180, max(5, napMinutes)) }
    }

    public init(
        kind: SessionKind = .night,
        mode: RecordingMode = .continuous,
        alarmEnabled: Bool = true,
        alarmHour: Int = 7,
        alarmMinute: Int = 0,
        smartWake: Bool = true,
        smartWindowMinutes: Int = 30,
        napMinutes: Int = 25
    ) {
        self.kind = kind
        self.mode = mode
        self.alarmEnabled = alarmEnabled
        self.alarmHour = min(23, max(0, alarmHour))
        self.alarmMinute = min(59, max(0, alarmMinute))
        self.smartWake = smartWake
        self.smartWindowMinutes = min(90, max(10, smartWindowMinutes))
        self.napMinutes = min(180, max(5, napMinutes))
    }

    /// Prochaine heure de réveil, strictement après `now`.
    public func nextAlarmDate(after now: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: now,
            matching: DateComponents(hour: alarmHour, minute: alarmMinute, second: 0),
            matchingPolicy: .nextTime
        )
    }

    /// Le réveil d'une session qui commencerait à `now` : la prochaine heure de réveil pour une nuit,
    /// la fin de la sieste pour une sieste (jamais de réveil intelligent pendant une sieste).
    public func alarm(startingAt now: Date, calendar: Calendar = .current) -> NightAlarm? {
        switch kind {
        case .nap:
            return NightAlarm(date: now.addingTimeInterval(TimeInterval(napMinutes * 60)))
        case .night:
            guard alarmEnabled, let date = nextAlarmDate(after: now, calendar: calendar) else { return nil }
            let window = smartWake ? max(now, date.addingTimeInterval(-TimeInterval(smartWindowMinutes * 60))) : nil
            return NightAlarm(date: date, smartWindowStart: window)
        }
    }
}

/// Préférences de la nuit, gardées par l'app d'une nuit à l'autre.
public protocol NightPreferencesStore: AnyObject, Sendable {
    /// Le type de session n'est pas gardé : chaque soir repart sur une nuit.
    var nightPlan: NightPlan { get set }
    var nightLighting: NightLighting { get }
    /// Nombre de nuits dont l'audio complet est gardé.
    var audioRetentionNights: Int { get }
}

/// Version en mémoire, pour les tests et les aperçus.
public final class InMemoryNightPreferences: NightPreferencesStore, @unchecked Sendable {
    public var nightPlan: NightPlan
    public var nightLighting: NightLighting
    public var audioRetentionNights: Int

    public init(nightPlan: NightPlan = NightPlan(), nightLighting: NightLighting = .dark, audioRetentionNights: Int = 30) {
        self.nightPlan = nightPlan
        self.nightLighting = nightLighting
        self.audioRetentionNights = audioRetentionNights
    }
}
