import Foundation
import Observation
import SleepDomain

/// Modèle de vue de « Ajouter une nuit » (maquette E23) : une nuit ou une sieste saisie à la main.
@MainActor
@Observable
final class AddNightViewModel {
    private(set) var kind: SessionKind = .night
    /// Le soir de la nuit, ou le jour de la sieste.
    var day: Date
    private(set) var times: [TimeField: ClockTime]
    var comment = ""
    private(set) var isSaving = false
    var errorMessage: String? = nil

    private let lifecycle: SessionLifecycle
    private let organizer: JournalOrganizer
    private let calendar: Calendar
    private let today: Date
    private let lastEvening: Date

    private static let nightDefaults: [TimeField: ClockTime] = [
        .bedtime: ClockTime(hour: 23, minute: 30),
        .sleepOnset: ClockTime(hour: 23, minute: 50),
        .wake: ClockTime(hour: 7, minute: 5),
        .getUp: ClockTime(hour: 7, minute: 15)
    ]

    private static let napDefaults: [TimeField: ClockTime] = [
        .bedtime: ClockTime(hour: 14, minute: 0),
        .sleepOnset: ClockTime(hour: 14, minute: 5),
        .wake: ClockTime(hour: 14, minute: 30),
        .getUp: ClockTime(hour: 14, minute: 35)
    ]

    init(lifecycle: SessionLifecycle, calendar: Calendar = .current, now: Date = Date()) {
        self.lifecycle = lifecycle
        self.organizer = JournalOrganizer(calendar: calendar)
        self.calendar = calendar
        self.today = calendar.startOfDay(for: now)
        // La nuit la plus probable à ajouter : la dernière nuit passée.
        let evening = NightCalendar(calendar: calendar).evening(at: now.addingTimeInterval(-12 * 3_600))
        self.lastEvening = evening
        self.day = evening
        self.times = Self.nightDefaults
    }

    func setKind(_ newKind: SessionKind) {
        guard newKind != kind else { return }
        kind = newKind
        times = newKind == .night ? Self.nightDefaults : Self.napDefaults
        day = newKind == .night ? lastEvening : today
    }

    var title: String {
        kind == .nap ? "Ajouter une sieste" : "Ajouter une nuit"
    }

    var dayLabel: String {
        kind == .nap ? "Jour" : "Nuit du"
    }

    /// La date la plus récente qu'on peut choisir.
    var latestDay: Date {
        kind == .nap ? today : lastEvening
    }

    func text(_ field: TimeField) -> String {
        guard let time = times[field] else { return "—" }
        return String(format: "%02d:%02d", time.hour, time.minute)
    }

    func initialTime(_ field: TimeField) -> Date {
        let time = times[field] ?? ClockTime(hour: 0, minute: 0)
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
    }

    func set(_ field: TimeField, hour: Int, minute: Int) {
        times[field] = ClockTime(hour: hour, minute: minute)
    }

    /// Les horaires placés sur les bons jours.
    var resolvedTimes: SessionTimes {
        organizer.manualTimes(
            kind: kind,
            day: day,
            bedtime: times[.bedtime] ?? ClockTime(hour: 23, minute: 0),
            sleepOnset: times[.sleepOnset],
            wake: times[.wake] ?? ClockTime(hour: 7, minute: 0),
            getUp: times[.getUp]
        )
    }

    /// « Sommeil estimé : 7 h 15 · au lit : 7 h 45. » ou « Sieste de 25 min · 30 min au total. »
    var summary: String {
        let preview = SleepSession(kind: kind, state: .manual, detected: resolvedTimes)
        if preview.issues.contains(.longerThanADay) {
            return "Vérifie les horaires : la session dépasserait 24 heures."
        }
        let format = organizer.format
        let asleep = preview.asleepDuration.map(format.duration) ?? "—"
        let inBed = preview.timeInBed.map(format.duration) ?? "—"
        if kind == .nap {
            return "Sieste de \(asleep) · \(inBed) au total."
        }
        return "Sommeil estimé : \(asleep) · au lit : \(inBed). Les réveils pourront être ajoutés ensuite."
    }

    func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await lifecycle.addManual(kind: kind, times: resolvedTimes, comment: comment)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
