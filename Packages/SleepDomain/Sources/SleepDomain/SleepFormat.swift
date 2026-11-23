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

    /// « jeu. 26 »
    public func weekdayAndDay(_ date: Date) -> String {
        formatter("EEE d").string(from: date)
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
