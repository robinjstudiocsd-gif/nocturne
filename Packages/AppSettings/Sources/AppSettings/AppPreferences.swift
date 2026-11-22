import Foundation
import SleepDomain

/// Apparence de l'app.
public enum Appearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// Éclairage de l'écran de nuit.
public enum NightLighting: String, CaseIterable, Sendable {
    case dark
    case red
}

/// Préférences typées, avec leurs valeurs par défaut, rangées dans UserDefaults.
public final class AppPreferences: @unchecked Sendable {
    public enum Key {
        static let appearance = "preferences.appearance"
        static let recordingMode = "preferences.recordingMode"
        static let audioRetentionNights = "preferences.audioRetentionNights"
        static let nightLighting = "preferences.nightLighting"
        static let sleepNeedMinutes = "preferences.sleepNeedMinutes"
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
