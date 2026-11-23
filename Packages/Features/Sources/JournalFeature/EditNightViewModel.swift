import Foundation
import Observation
import SleepDomain

/// Les quatre horaires d'une session.
enum TimeField: String, CaseIterable, Identifiable {
    case bedtime
    case sleepOnset
    case wake
    case getUp

    var id: String { rawValue }

    func title(for kind: SessionKind) -> String {
        switch self {
        case .bedtime: kind == .nap ? "Début" : "Coucher"
        case .sleepOnset: "Endormissement"
        case .wake: "Réveil"
        case .getUp: kind == .nap ? "Fin" : "Lever"
        }
    }

    func value(in times: SessionTimes) -> Date? {
        switch self {
        case .bedtime: times.bedtime
        case .sleepOnset: times.sleepOnset
        case .wake: times.wake
        case .getUp: times.getUp
        }
    }

    func set(_ date: Date?, in times: inout SessionTimes) {
        switch self {
        case .bedtime: times.bedtime = date
        case .sleepOnset: times.sleepOnset = date
        case .wake: times.wake = date
        case .getUp: times.getUp = date
        }
    }
}

/// Modèle de vue de « Modifier une nuit » (maquette E22) : corrections, réveils, type, ressenti, commentaire, suppression.
/// Une correction ne touche jamais la détection : « Rétablir » la retire.
@MainActor
@Observable
final class EditNightViewModel {
    let original: SleepSession
    private(set) var corrected: SessionTimes
    var kind: SessionKind
    private(set) var wakeEpisodes: [WakeEpisode]
    var mood: Int? = nil
    var energy: Int? = nil
    var comment: String
    private(set) var isSaving = false
    var errorMessage: String? = nil

    private let dependencies: JournalDependencies
    private let format: SleepFormat
    private let nightCalendar: NightCalendar

    init(session: SleepSession, dependencies: JournalDependencies, calendar: Calendar = .current) {
        self.original = session
        self.corrected = session.corrected
        self.kind = session.kind
        self.wakeEpisodes = session.wakeEpisodes
        self.mood = session.feeling?.mood
        self.energy = session.feeling?.energy
        self.comment = session.comment ?? ""
        self.dependencies = dependencies
        self.format = SleepFormat(calendar: calendar)
        self.nightCalendar = NightCalendar(calendar: calendar)
    }

    /// Horaires retenus avec les corrections en cours.
    private var retained: SessionTimes {
        corrected.overriding(original.detected)
    }

    var title: String {
        var copy = original
        copy.kind = kind
        return nightCalendar.title(of: copy)
    }

    var navigationTitle: String {
        kind == .nap ? "Modifier la sieste" : "Modifier la nuit"
    }

    // MARK: - Horaires

    func isCorrected(_ field: TimeField) -> Bool {
        guard let value = field.value(in: corrected) else { return false }
        return value != field.value(in: original.detected)
    }

    func valueText(_ field: TimeField) -> String {
        field.value(in: retained).map(format.clock) ?? "À préciser"
    }

    /// « détecté 00:47 », « corrigé · détecté 01:05 », « saisi 23:30 », « non détecté ».
    func detail(_ field: TimeField) -> String {
        let word = original.state == .manual ? "saisi" : "détecté"
        let detected = field.value(in: original.detected).map { "\(word) \(format.clock($0))" } ?? "non \(word)"
        return isCorrected(field) ? "corrigé · \(detected)" : detected
    }

    func initialTime(_ field: TimeField) -> Date {
        field.value(in: retained) ?? retained.bedtime ?? original.referenceDate
    }

    /// Place l'heure choisie sur la bonne journée de la nuit ; une heure égale à la détection n'est pas une correction.
    func set(_ field: TimeField, hour: Int, minute: Int) {
        let date = nightCalendar.place(hour: hour, minute: minute, near: window)
        field.set(date == field.value(in: original.detected) ? nil : date, in: &corrected)
    }

    func restore(_ field: TimeField) {
        field.set(nil, in: &corrected)
    }

    /// La nuit, du coucher au lever retenus.
    private var window: DateInterval {
        let times = retained
        let start = times.bedtime ?? times.sleepOnset ?? original.referenceDate
        let end = times.getUp ?? times.wake ?? start.addingTimeInterval(8 * 3_600)
        return DateInterval(start: start, end: max(start, end))
    }

    // MARK: - Réveils

    func wakeText(_ episode: WakeEpisode) -> String {
        "\(format.clock(episode.start)) · \(format.duration(episode.duration))"
    }

    var wakeSuggestion: Date {
        let times = retained
        let start = times.sleepOnset ?? times.bedtime ?? original.referenceDate
        let end = times.wake ?? times.getUp ?? start.addingTimeInterval(8 * 3_600)
        return start.addingTimeInterval(max(0, end.timeIntervalSince(start)) / 2)
    }

    func addWake(hour: Int, minute: Int, minutes: Int) {
        let times = retained
        let start = times.sleepOnset ?? times.bedtime ?? original.referenceDate
        let end = times.wake ?? times.getUp ?? start.addingTimeInterval(8 * 3_600)
        let begin = nightCalendar.place(hour: hour, minute: minute, near: DateInterval(start: start, end: max(start, end)))
        wakeEpisodes.append(WakeEpisode(start: begin, end: begin.addingTimeInterval(TimeInterval(max(1, minutes) * 60))))
        wakeEpisodes.sort { $0.start < $1.start }
    }

    func removeWake(_ episode: WakeEpisode) {
        wakeEpisodes.removeAll { $0.id == episode.id }
    }

    // MARK: - Ressenti

    var moodText: String {
        mood.map(WakeFeeling.moodLabel) ?? "Non renseignée"
    }

    var energyText: String {
        energy.map { "\($0) sur 5" } ?? "Non renseignée"
    }

    // MARK: - Enregistrer, supprimer

    func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await dependencies.lifecycle.saveEdit(
                id: original.id,
                corrected: corrected,
                wakeEpisodes: wakeEpisodes,
                kind: kind,
                feeling: WakeFeeling(mood: mood, energy: energy),
                comment: comment
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await dependencies.lifecycle.delete(id: original.id, erasing: dependencies.eraser)
            return true
        } catch {
            errorMessage = "La nuit n’a pas pu être supprimée : \(error.localizedDescription)"
            return false
        }
    }
}
