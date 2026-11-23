import Foundation
import Observation
import SleepDomain

/// Modèle de vue de « Bonjour » : résumé de la nuit, ressenti, horaires corrigés et commentaire.
@MainActor
@Observable
public final class MorningViewModel {
    public enum TimeField: String, Identifiable {
        case sleepOnset
        case wake

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .sleepOnset: "Endormissement"
            case .wake: "Réveil"
            }
        }
    }

    public let session: SleepSession
    /// État de l'écoute à l'arrêt : tranches, trous.
    public let snapshot: NightStatus
    public var mood: Int? = nil
    public var energy: Int? = nil
    public var comment: String
    public private(set) var onsetOverride: Date? = nil
    public private(set) var wakeOverride: Date? = nil
    public private(set) var isSaving = false
    public var errorMessage: String? = nil

    private let lifecycle: SessionLifecycle
    private let format: SleepFormat
    private let nightCalendar: NightCalendar
    private let now: () -> Date

    public init(
        session: SleepSession,
        snapshot: NightStatus,
        lifecycle: SessionLifecycle,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.session = session
        self.snapshot = snapshot
        self.lifecycle = lifecycle
        self.format = SleepFormat(calendar: calendar)
        self.nightCalendar = NightCalendar(calendar: calendar)
        self.now = now
        self.mood = session.feeling?.mood
        self.energy = session.feeling?.energy
        self.comment = session.comment ?? ""
    }

    /// Horaires corrigés : la détection d'origine reste intacte.
    private var correctedTimes: SessionTimes {
        var times = session.corrected
        if let onsetOverride {
            times.sleepOnset = onsetOverride
        }
        if let wakeOverride {
            times.wake = wakeOverride
            // On ne se lève pas avant de se réveiller.
            if let getUp = session.times.getUp, wakeOverride > getUp {
                times.getUp = wakeOverride
            }
        }
        return times
    }

    /// La session telle qu'elle sera enregistrée.
    private var preview: SleepSession {
        var copy = session
        copy.corrected = correctedTimes
        return copy
    }

    // MARK: - Textes

    public var dayTitle: String {
        format.dayTitle(preview.times.wake ?? now())
    }

    public var headline: String {
        let night = preview
        if let asleep = night.asleepDuration {
            return "\(format.duration(asleep)) de sommeil"
        }
        if let inBed = night.timeInBed {
            return "\(format.duration(inBed)) au lit"
        }
        return session.kind == .nap ? "Sieste terminée" : "Nuit terminée"
    }

    public var timesLine: String? {
        let night = preview
        guard let start = night.times.sleepOnset ?? night.times.bedtime, let end = night.times.wake else { return nil }
        var text = "\(format.clock(start)) → \(format.clock(end))"
        let wakes = night.significantWakeCount
        if wakes > 0 {
            text += " · \(wakes) réveil\(wakes > 1 ? "s" : "")"
        }
        return text
    }

    public var listeningLine: String {
        guard snapshot.mode != .off else { return "Micro coupé : horaires seulement" }
        let listened = format.duration(snapshot.listenedDuration(until: now()))
        let gaps = snapshot.gaps
        guard !gaps.isEmpty else { return "\(listened) d’écoute, sans coupure" }
        let missing = gaps.reduce(0) { $0 + $1.duration }
        return "\(listened) d’écoute · \(gaps.count) coupure\(gaps.count > 1 ? "s" : "") (\(format.duration(missing)))"
    }

    /// « 17 événements sonores »
    public var eventsLine: String? {
        guard snapshot.mode != .off else { return nil }
        switch snapshot.eventCount {
        case 0: return "Aucun événement sonore"
        case 1: return "1 événement sonore"
        default: return "\(snapshot.eventCount) événements sonores"
        }
    }

    /// Vrai si l'app s'est arrêtée pendant la nuit et que la fin a été estimée.
    public var wasInterrupted: Bool {
        session.state == .interrupted
    }

    public func text(for field: TimeField) -> String {
        let times = preview.times
        let date = field == .sleepOnset ? times.sleepOnset : times.wake
        return date.map(format.clock) ?? "À préciser"
    }

    public func accessibilityText(for field: TimeField) -> String {
        "Corriger l’heure \(field == .sleepOnset ? "d’endormissement" : "de réveil"), \(text(for: field))"
    }

    // MARK: - Corrections

    public func initialTime(for field: TimeField) -> Date {
        let times = preview.times
        switch field {
        case .sleepOnset: return times.sleepOnset ?? times.bedtime ?? now()
        case .wake: return times.wake ?? now()
        }
    }

    /// Place l'heure choisie sur la bonne journée de la nuit.
    public func set(_ field: TimeField, hour: Int, minute: Int) {
        let times = preview.times
        let bedtime = times.bedtime ?? session.createdAt
        let stop = session.detected.getUp ?? session.detected.wake ?? times.wake ?? now()
        switch field {
        case .sleepOnset:
            let end = max(bedtime, times.wake ?? stop)
            onsetOverride = nightCalendar.place(hour: hour, minute: minute, near: DateInterval(start: bedtime, end: end))
        case .wake:
            let start = times.sleepOnset ?? bedtime
            wakeOverride = nightCalendar.place(hour: hour, minute: minute, near: DateInterval(start: start, end: max(start, stop)))
        }
    }

    /// Enregistre le tout ; renvoie faux si les horaires ne vont pas.
    public func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await lifecycle.saveMorning(
                id: session.id,
                feeling: WakeFeeling(mood: mood, energy: energy),
                corrected: correctedTimes,
                comment: comment
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
