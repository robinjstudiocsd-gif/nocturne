import Foundation

/// Textes de la fiche de nuit : en-tête, résumé des horaires, écoute, ressenti et journal du soir.
public struct NightDetailText: Sendable {
    public let format: SleepFormat
    public let nightCalendar: NightCalendar

    public init(calendar: Calendar = .current) {
        self.format = SleepFormat(calendar: calendar)
        self.nightCalendar = NightCalendar(calendar: calendar)
    }

    /// « Samedi 21 → dimanche 22 » et « novembre 2026 » ; « Sieste du vendredi 20 ».
    public func header(_ session: SleepSession) -> (title: String, subtitle: String) {
        let evening = nightCalendar.evening(of: session)
        guard session.kind == .night else {
            return ("Sieste du \(format.weekdayDay(evening))", format.monthYear(evening))
        }
        let morning = nightCalendar.morning(of: session)
        let start = format.weekdayDay(evening)
        let title = start.prefix(1).uppercased() + start.dropFirst() + " → " + format.weekdayDay(morning)
        let calendar = nightCalendar.calendar
        let subtitle: String
        if calendar.component(.month, from: evening) == calendar.component(.month, from: morning) {
            subtitle = format.monthYear(morning)
        } else if calendar.component(.year, from: evening) == calendar.component(.year, from: morning) {
            let first = format.monthYear(evening).split(separator: " ").first.map(String.init) ?? ""
            subtitle = "\(first) et \(format.monthYear(morning))"
        } else {
            subtitle = "\(format.monthYear(evening)) et \(format.monthYear(morning))"
        }
        return (title, subtitle)
    }

    /// « Endormissement en 18 min. Un réveil de plus de 5 min, à 04:46, pendant 7 min. »
    public func summary(_ session: SleepSession) -> String? {
        var sentences: [String] = []
        if let latency = session.sleepLatency {
            sentences.append("Endormissement en \(format.duration(latency)).")
        }
        let wakes = session.wakeEpisodes.filter(\.isSignificant)
        if wakes.count == 1, let wake = wakes.first {
            sentences.append("Un réveil de plus de 5 min, à \(format.clock(wake.start)), pendant \(format.duration(wake.duration)).")
        } else if wakes.count > 1 {
            let total = wakes.reduce(0) { $0 + $1.duration }
            sentences.append("\(wakes.count) réveils de plus de 5 min, \(format.duration(total)) en tout.")
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    /// « 8 h 33 enregistrées · aucune coupure · 123 Mo »
    public func listening(_ session: SleepSession, gaps: [RecordingGap], bytes: Int64, now: Date) -> String {
        guard session.recordingMode != .off else { return "Micro coupé : pas d’enregistrement" }
        var parts = ["\(format.duration(session.listenedDuration(gaps: gaps, until: now))) enregistrées"]
        if gaps.isEmpty {
            parts.append("aucune coupure")
        } else {
            let total = gaps.reduce(0) { $0 + $1.duration }
            parts.append("\(gaps.count) coupure\(gaps.count > 1 ? "s" : "") (\(format.duration(total)))")
        }
        if bytes > 0 {
            parts.append(format.bytes(bytes))
        }
        return parts.joined(separator: " · ")
    }

    /// « Coupure à 02:31 · 12 min · appel »
    public func gap(_ gap: RecordingGap) -> String {
        "Coupure à \(format.clock(gap.start)) · \(format.duration(gap.duration)) · \(gap.cause.shortLabel)"
    }

    // MARK: - Journal du soir

    public func caffeine(_ log: EveningLog) -> String? {
        guard let caffeine = log.caffeine else { return nil }
        let count: String
        switch caffeine {
        case .none: return "Aucune"
        case .one: count = "1 café"
        case .two: count = "2 cafés"
        case .threeOrMore: count = "3 cafés ou plus"
        }
        guard let last = log.lastCaffeine else { return count }
        return caffeine == .one ? "\(count) à \(format.clock(last))" : "\(count), le dernier à \(format.clock(last))"
    }

    public func exercise(_ log: EveningLog) -> String? {
        guard let exercise = log.exercise else { return nil }
        let text: String
        switch exercise {
        case .none: return "Non"
        case .light: text = "Léger"
        case .intense: text = "Intense"
        }
        return log.exerciseEnd.map { "\(text), fini à \(format.clock($0))" } ?? text
    }

    public func screens(_ log: EveningLog) -> String? {
        switch log.screens {
        case .offEarly: "Coupés tôt"
        case .untilBedtime: "Jusqu’au coucher"
        case .inBed: "Au lit"
        case nil: nil
        }
    }

    public func stress(_ log: EveningLog) -> String? {
        guard let stress = log.stress else { return nil }
        return ["Très faible", "Faible", "Moyen", "Élevé", "Très élevé"][min(5, max(1, stress)) - 1]
    }

    public func meal(_ log: EveningLog) -> String? {
        guard let meal = log.meal else { return nil }
        let text: String
        switch meal {
        case .light: text = "Léger"
        case .normal: text = "Normal"
        case .heavy: text = "Copieux"
        }
        return log.mealEnd.map { "\(text), fini à \(format.clock($0))" } ?? text
    }
}
