import Foundation

/// Un jour de la dette de sommeil.
public struct SleepDebtDay: Equatable, Sendable {
    public var day: Date
    /// Sommeil du jour (nuit qui s'y termine et siestes), ou nil sans nuit mesurée.
    public var slept: TimeInterval?
    /// Sommeil moins besoin : négatif quand il a manqué du sommeil.
    public var balance: TimeInterval?
}

/// Dette de sommeil sur 14 jours (étude, E12) : écart cumulé entre ton besoin et ton sommeil, jour par jour.
/// Un jour sans nuit mesurée ne compte pas : on ne devine jamais un sommeil absent.
public struct SleepDebt: Equatable, Sendable {
    public var days: [SleepDebtDay]
    /// Dette en secondes, jamais négative.
    public var total: TimeInterval

    public static func compute(sessions: [SleepSession], need: TimeInterval, through end: Date, days count: Int = 14, calendar: Calendar = .current) -> SleepDebt {
        let nightCalendar = NightCalendar(calendar: calendar)
        let last = calendar.startOfDay(for: end)
        var byDay: [Date: (night: Bool, slept: TimeInterval)] = [:]
        for session in sessions where session.state != .running {
            guard let asleep = session.asleepDuration else { continue }
            let day = calendar.startOfDay(for: nightCalendar.morning(of: session))
            var entry = byDay[day] ?? (night: false, slept: 0)
            entry.slept += asleep
            entry.night = entry.night || session.kind == .night
            byDay[day] = entry
        }
        let days: [SleepDebtDay] = (0..<max(1, count)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: last) else { return nil }
            guard let entry = byDay[day], entry.night else {
                return SleepDebtDay(day: day, slept: nil, balance: nil)
            }
            return SleepDebtDay(day: day, slept: entry.slept, balance: entry.slept - need)
        }
        let sum = days.compactMap(\.balance).reduce(0, +)
        return SleepDebt(days: days, total: max(0, -sum))
    }
}
