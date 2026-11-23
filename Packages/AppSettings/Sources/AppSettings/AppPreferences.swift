import Foundation
import SleepDomain

/// Apparence de l'app.
public enum Appearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// Préférences typées, avec leurs valeurs par défaut, rangées dans UserDefaults.
public final class AppPreferences: @unchecked Sendable {
    public enum Key {
        static let appearance = "preferences.appearance"
        static let recordingMode = "preferences.recordingMode"
        static let audioRetentionNights = "preferences.audioRetentionNights"
        static let nightLighting = "preferences.nightLighting"
        static let sleepNeedMinutes = "preferences.sleepNeedMinutes"
        static let alarmEnabled = "preferences.alarm.enabled"
        static let alarmHour = "preferences.alarm.hour"
        static let alarmMinute = "preferences.alarm.minute"
        static let smartWake = "preferences.alarm.smartWake"
        static let napMinutes = "preferences.nap.minutes"
    }

    /// Valeurs par défaut validées dans l'étude.
    public enum Default {
        public static let audioRetentionNights = 30
        public static let sleepNeedMinutes = 450
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var appearance: Appearance {
        get { defaults.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .dark }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    public var recordingMode: RecordingMode {
        get { defaults.string(forKey: Key.recordingMode).flatMap(RecordingMode.init(rawValue:)) ?? .continuous }
        set { defaults.set(newValue.rawValue, forKey: Key.recordingMode) }
    }

    /// Nombre de nuits dont l'audio complet est gardé (30 par défaut, de 1 à 365).
    public var audioRetentionNights: Int {
        get {
            let stored = defaults.object(forKey: Key.audioRetentionNights) as? Int ?? Default.audioRetentionNights
            return min(365, max(1, stored))
        }
        set { defaults.set(min(365, max(1, newValue)), forKey: Key.audioRetentionNights) }
    }

    public var nightLighting: NightLighting {
        get { defaults.string(forKey: Key.nightLighting).flatMap(NightLighting.init(rawValue:)) ?? .dark }
        set { defaults.set(newValue.rawValue, forKey: Key.nightLighting) }
    }

    /// Besoin de sommeil par nuit, en minutes (7 h 30 par défaut), pour la dette de sommeil.
    public var sleepNeedMinutes: Int {
        get {
            let stored = defaults.object(forKey: Key.sleepNeedMinutes) as? Int ?? Default.sleepNeedMinutes
            return min(720, max(240, stored))
        }
        set { defaults.set(min(720, max(240, newValue)), forKey: Key.sleepNeedMinutes) }
    }
}

extension AppPreferences: NightPreferencesStore {
    /// Réglages de « Préparer ma nuit » gardés d'un soir à l'autre ; le type de session repart toujours sur une nuit.
    public var nightPlan: NightPlan {
        get {
            let base = NightPlan()
            return NightPlan(
                kind: .night,
                mode: recordingMode,
                alarmEnabled: defaults.object(forKey: Key.alarmEnabled) as? Bool ?? base.alarmEnabled,
                alarmHour: defaults.object(forKey: Key.alarmHour) as? Int ?? base.alarmHour,
                alarmMinute: defaults.object(forKey: Key.alarmMinute) as? Int ?? base.alarmMinute,
                smartWake: defaults.object(forKey: Key.smartWake) as? Bool ?? base.smartWake,
                smartWindowMinutes: base.smartWindowMinutes,
                napMinutes: defaults.object(forKey: Key.napMinutes) as? Int ?? base.napMinutes
            )
        }
        set {
            recordingMode = newValue.mode
            defaults.set(newValue.alarmEnabled, forKey: Key.alarmEnabled)
            defaults.set(newValue.alarmHour, forKey: Key.alarmHour)
            defaults.set(newValue.alarmMinute, forKey: Key.alarmMinute)
            defaults.set(newValue.smartWake, forKey: Key.smartWake)
            defaults.set(newValue.napMinutes, forKey: Key.napMinutes)
        }
    }
}
