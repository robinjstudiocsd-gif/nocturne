import Foundation

/// Textes des heures, des jours, des durées et des tailles, en français et toujours au même format.
public struct SleepFormat: Sendable {
    public let calendar: Calendar
    public let locale: Locale

    public init(calendar: Calendar = .current, locale: Locale = Locale(identifier: "fr_FR")) {
        self.calendar = calendar
        self.locale = locale
    }

    /// « 07:00 »
    public func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// « 4 h 13 », « 7 h », « 45 min ». Arrondi à la minute.
    public func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 {
            return "\(rest) min"
        }
        if rest == 0 {
            return "\(hours) h"
        }
        return String(format: "%d h %02d", hours, rest)
    }

    /// « 6 s », « 2 min 10 », « 1 h 05 » : pour les sons, souvent courts.
    public func span(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 {
            return "\(seconds) s"
        }
        if seconds < 3_600 {
            return String(format: "%d min %02d", seconds / 60, seconds % 60)
        }
        return String(format: "%d h %02d", seconds / 3_600, (seconds % 3_600) / 60)
    }

    /// « 7h51 », « 45 min » : pour les petites cases du calendrier.
    public func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        guard minutes >= 60 else { return "\(minutes) min" }
        return String(format: "%dh%02d", minutes / 60, minutes % 60)
    }

    /// « lundi 23 novembre »
    public func longDay(_ date: Date) -> String {
        formatter("EEEE d MMMM").string(from: date)
    }

    /// « Lundi 23 novembre »
    public func dayTitle(_ date: Date) -> String {
        let text = longDay(date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// « lun. 07:00 »
    public func weekdayAndClock(_ date: Date) -> String {
        "\(formatter("EEE").string(from: date)) \(clock(date))"
    }

    /// « lun. »
    public func shortWeekday(_ date: Date) -> String {
        formatter("EEE").string(from: date)
    }

    /// « jeu. 26 »
    public func weekdayAndDay(_ date: Date) -> String {
        formatter("EEE d").string(from: date)
    }

    /// « samedi 21 »
    public func weekdayDay(_ date: Date) -> String {
        formatter("EEEE d").string(from: date)
    }

    /// « novembre 2026 »
    public func monthYear(_ date: Date) -> String {
        formatter("LLLL yyyy").string(from: date)
    }

    /// « 41 Go », « 4,2 Go », « 820 Mo », comme dans les réglages de l'iPhone.
    public func bytes(_ count: Int64) -> String {
        let value = Double(max(0, count))
        if value >= 10_000_000_000 {
            return "\(Int((value / 1_000_000_000).rounded())) Go"
        }
        if value >= 1_000_000_000 {
            let text = String(format: "%.1f", value / 1_000_000_000).replacingOccurrences(of: ".", with: ",")
            return "\(text) Go"
        }
        return "\(max(1, Int((value / 1_000_000).rounded()))) Mo"
    }

    private func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}

/// Repère d'heure sous un graphique de la nuit.
public struct HourTick: Hashable, Sendable {
    /// « 02:00 »
    public var label: String
    /// Place du repère, de 0 (début de la nuit) à 1 (fin).
    public var fraction: Double

    public init(label: String, fraction: Double) {
        self.label = label
        self.fraction = fraction
    }
}

extension SleepFormat {
    /// Repères des heures pleines entre deux heures : toutes les 2 heures (toutes les heures pour moins de 4 heures),
    /// sans ceux qui toucheraient les bords.
    public func hourTicks(from start: Date, to end: Date) -> [HourTick] {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return [] }
        let everyHour = duration <= 4 * 3_600
        var hour = calendar.dateInterval(of: .hour, for: start)?.end ?? start
        var ticks: [HourTick] = []
        while hour < end {
            let fraction = hour.timeIntervalSince(start) / duration
            if everyHour || calendar.component(.hour, from: hour) % 2 == 0, fraction > 0.04, fraction < 0.96 {
                ticks.append(HourTick(label: clock(hour), fraction: fraction))
            }
            hour = hour.addingTimeInterval(3_600)
        }
        return ticks
    }
}
