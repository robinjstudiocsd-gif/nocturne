import Foundation
import Observation
import SleepDomain

/// Modèle de vue du journal du soir : caféine, sport, écrans, repas, stress et note.
@MainActor
@Observable
public final class EveningLogViewModel {
    public enum TimeField: String, Identifiable {
        case caffeine
        case exercise
        case meal

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .caffeine: "Dernière caféine"
            case .exercise: "Fin du sport"
            case .meal: "Fin du repas"
            }
        }

        /// Heure proposée sur la roue quand rien n'est encore saisi.
        var suggestedHour: Int {
            switch self {
            case .caffeine: 16
            case .exercise: 18
            case .meal: 20
            }
        }
    }

    /// Le soir concerné, ramené au début de la journée.
    public let day: Date
    public var caffeine: EveningLog.Caffeine? = nil
    public var lastCaffeine: Date? = nil
    public var exercise: EveningLog.Exercise? = nil
    public var exerciseEnd: Date? = nil
    public var screens: EveningLog.Screens? = nil
    public var meal: EveningLog.Meal? = nil
    public var mealEnd: Date? = nil
    public var stress: Int? = nil
    public var note = ""
    public private(set) var isSaving = false
    public var errorMessage: String? = nil

    private let repository: any EveningLogRepository
    private let format: SleepFormat
    private let nightCalendar: NightCalendar
    private let openedAt: Date
    private var existingID: UUID? = nil

    public init(repository: any EveningLogRepository, calendar: Calendar = .current, now: Date = Date()) {
        self.repository = repository
        self.format = SleepFormat(calendar: calendar)
        self.nightCalendar = NightCalendar(calendar: calendar)
        self.openedAt = now
        self.day = NightCalendar(calendar: calendar).evening(at: now)
    }

    /// « Dimanche 22 novembre · 22:40 »
    public var headerLine: String {
        "\(format.dayTitle(day)) · \(format.clock(openedAt))"
    }

    public func load() async {
        guard let log = try? await repository.log(forDay: day) else { return }
        existingID = log.id
        caffeine = log.caffeine
        lastCaffeine = log.lastCaffeine
        exercise = log.exercise
        exerciseEnd = log.exerciseEnd
        screens = log.screens
        meal = log.meal
        mealEnd = log.mealEnd
        stress = log.stress
        note = log.note ?? ""
    }

    // MARK: - Heures

    /// Vrai quand l'heure a un sens : de la caféine bue, du sport fait, un repas pris.
    public func showsTime(_ field: TimeField) -> Bool {
        switch field {
        case .caffeine: caffeine != nil && caffeine != EveningLog.Caffeine.none
        case .exercise: exercise != nil && exercise != EveningLog.Exercise.none
        case .meal: meal != nil
        }
    }

    public func timeText(_ field: TimeField) -> String {
        let prefix = field == .caffeine ? "dernière à" : "fini à"
        guard let date = time(field) else { return "Ajouter l’heure" }
        return "\(prefix) \(format.clock(date))"
    }

    public func time(_ field: TimeField) -> Date? {
        switch field {
        case .caffeine: lastCaffeine
        case .exercise: exerciseEnd
        case .meal: mealEnd
        }
    }

    public func initialTime(_ field: TimeField) -> Date {
        if let date = time(field) {
            return date
        }
        return format.calendar.date(bySettingHour: field.suggestedHour, minute: 0, second: 0, of: day) ?? day
    }

    /// Place l'heure sur la soirée : de 6 h du matin du jour à 4 h du matin le lendemain.
    public func setTime(_ field: TimeField, hour: Int, minute: Int) {
        let start = day.addingTimeInterval(6 * 3_600)
        let evening = DateInterval(start: start, end: day.addingTimeInterval(28 * 3_600))
        let date = nightCalendar.place(hour: hour, minute: minute, near: evening)
        switch field {
        case .caffeine: lastCaffeine = date
        case .exercise: exerciseEnd = date
        case .meal: mealEnd = date
        }
    }

    public func clearTime(_ field: TimeField) {
        switch field {
        case .caffeine: lastCaffeine = nil
        case .exercise: exerciseEnd = nil
        case .meal: mealEnd = nil
        }
    }

    // MARK: - Enregistrer

    /// Enregistre le journal ; un journal vidé est supprimé.
    public func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        let log = EveningLog(
            id: existingID ?? UUID(),
            day: day,
            caffeine: caffeine,
            lastCaffeine: showsTime(.caffeine) ? lastCaffeine : nil,
            exercise: exercise,
            exerciseEnd: showsTime(.exercise) ? exerciseEnd : nil,
            screens: screens,
            stress: stress,
            meal: meal,
            mealEnd: showsTime(.meal) ? mealEnd : nil,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines),
            calendar: format.calendar
        )
        do {
            if log.isEmpty {
                if let existingID {
                    try await repository.delete(id: existingID)
                }
            } else {
                try await repository.save(log)
            }
            return true
        } catch {
            errorMessage = "Le journal n’a pas pu être enregistré : \(error.localizedDescription)"
            return false
        }
    }
}
