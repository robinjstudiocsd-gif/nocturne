import Foundation

/// Rattache une session à sa nuit : le soir où elle commence et le matin où elle finit.
public struct NightCalendar: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Le soir de la nuit : un coucher après minuit et avant midi appartient à la veille.
    public func evening(of session: SleepSession) -> Date {
        let reference = session.referenceDate
        guard session.kind == .night else { return calendar.startOfDay(for: reference) }
        return evening(at: reference)
    }

    /// Le soir auquel rattacher un moment : avant midi, c'est encore la soirée de la veille.
    public func evening(at date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let hour = calendar.component(.hour, from: date)
        return hour < 12 ? (calendar.date(byAdding: .day, value: -1, to: day) ?? day) : day
    }

    /// Place une heure saisie (« 23:41 ») sur le bon jour : dans l'intervalle si possible, sinon au plus près.
    public func place(hour: Int, minute: Int, near interval: DateInterval) -> Date {
        let firstDay = calendar.startOfDay(for: interval.start)
        var best = interval.start
        var bestDistance = TimeInterval.infinity
        for offset in -1...2 {
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
            else { continue }
            let distance: TimeInterval
            if candidate < interval.start {
                distance = interval.start.timeIntervalSince(candidate)
            } else if candidate > interval.end {
                distance = candidate.timeIntervalSince(interval.end)
            } else {
                distance = 0
            }
            if distance < bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }

    /// Le matin de la nuit, c'est-à-dire le lendemain du soir (ou le jour même pour une sieste).
    public func morning(of session: SleepSession) -> Date {
        let evening = evening(of: session)
        guard session.kind == .night else { return evening }
        return calendar.date(byAdding: .day, value: 1, to: evening) ?? evening
    }

    /// Titre lisible : « Nuit du samedi 21 au dimanche 22 novembre » ou « Sieste du vendredi 20 novembre ».
    public func title(of session: SleepSession, locale: Locale = Locale(identifier: "fr_FR")) -> String {
        let dayAndNumber = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide).day()
        let full = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide).day().month(.wide)
        if session.kind == .nap {
            return "Sieste du \(evening(of: session).formatted(full))"
        }
        return "Nuit du \(evening(of: session).formatted(dayAndNumber)) au \(morning(of: session).formatted(full))"
    }
}
