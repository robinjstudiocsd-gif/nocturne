import Foundation

/// Filtre du journal des nuits.
public enum JournalFilter: String, CaseIterable, Sendable {
    case all
    case nights
    case naps

    public var title: String {
        switch self {
        case .all: "Tout"
        case .nights: "Nuits"
        case .naps: "Siestes"
        }
    }

    public func includes(_ session: SleepSession) -> Bool {
        switch self {
        case .all: true
        case .nights: session.kind == .night
        case .naps: session.kind == .nap
        }
    }
}

/// Une semaine du journal, du lundi au dimanche.
public struct JournalWeek: Identifiable, Equatable, Sendable {
    public var start: Date
    public var title: String
    public var sessions: [SleepSession]

    public var id: Date { start }
}

/// Un jour du calendrier du journal.
public struct JournalDay: Identifiable, Equatable, Sendable {
    public var date: Date
    public var dayNumber: Int
    public var isInMonth: Bool
    public var isToday: Bool
    public var isFuture: Bool
    /// Les nuits qui se terminent ce jour-là et les siestes du jour, la plus récente d'abord.
    public var sessions: [SleepSession]

    public var id: Date { date }
}

/// Une heure saisie, sans jour.
public struct ClockTime: Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}

/// Organisation du journal : semaines, calendrier, recherche, textes des lignes.
public struct JournalOrganizer: Sendable {
    public let nightCalendar: NightCalendar
    public let format: SleepFormat

    public init(calendar: Calendar = .current) {
        self.nightCalendar = NightCalendar(calendar: calendar)
        self.format = SleepFormat(calendar: calendar)
    }

    /// Calendrier à semaines commençant le lundi.
    private var weekCalendar: Calendar {
        var calendar = nightCalendar.calendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// Le jour affiché pour une session : le matin pour une nuit, le jour même pour une sieste.
    public func displayDay(of session: SleepSession) -> Date {
        nightCalendar.morning(of: session)
    }

    // MARK: - Semaines

    /// Les sessions groupées par semaine, de la plus récente à la plus ancienne.
    public func weeks(_ sessions: [SleepSession], now: Date) -> [JournalWeek] {
        let calendar = weekCalendar
        let sorted = sessions.sorted { $0.referenceDate > $1.referenceDate }
        var weeks: [JournalWeek] = []
        for session in sorted {
            let start = calendar.dateInterval(of: .weekOfYear, for: displayDay(of: session))?.start ?? displayDay(of: session)
            if let last = weeks.indices.last, weeks[last].start == start {
                weeks[last].sessions.append(session)
            } else {
                weeks.append(JournalWeek(start: start, title: weekTitle(start, now: now), sessions: [session]))
            }
        }
        return weeks
    }

    /// « Cette semaine », « La semaine dernière », « Semaine du 9 novembre ».
    public func weekTitle(_ start: Date, now: Date) -> String {
        let calendar = weekCalendar
        let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        if start == current {
            return "Cette semaine"
        }
        if let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: current), start == previous {
            return "La semaine dernière"
        }
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: now)
        let day = format.longDay(start).split(separator: " ").dropFirst().joined(separator: " ")
        return sameYear ? "Semaine du \(day)" : "Semaine du \(day) \(calendar.component(.year, from: start))"
    }

    // MARK: - Recherche

    /// Vrai si le commentaire ou le titre de la nuit contient le texte cherché (sans tenir compte des accents).
    public func matches(_ session: SleepSession, query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        let haystack = [session.comment ?? "", nightCalendar.title(of: session)].joined(separator: " ")
        return haystack.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: - Lignes

    /// « Nuit · 7 h 51 », « Sieste · 25 min », « Nuit · en cours ».
    public func rowTitle(_ session: SleepSession) -> String {
        let kind = session.kind == .nap ? "Sieste" : "Nuit"
        if session.state == .running {
            return "\(kind) · en cours"
        }
        guard let duration = session.asleepDuration ?? session.timeInBed else { return kind }
        return "\(kind) · \(format.duration(duration))"
    }

    /// « 00:47 → 09:20 · saisie »
    public func rowSubtitle(_ session: SleepSession) -> String {
        var parts: [String] = []
        let times = session.times
        if let start = times.sleepOnset ?? times.bedtime {
            if let end = times.wake ?? times.getUp {
                parts.append("\(format.clock(start)) → \(format.clock(end))")
            } else {
                parts.append("depuis \(format.clock(start))")
            }
        }
        switch session.state {
        case .manual: parts.append("saisie")
        case .interrupted: parts.append("fin estimée")
        case .imported: parts.append("importée")
        case .running, .finished: break
        }
        return parts.joined(separator: " · ")
    }

    /// « Écoute coupée 12 min (appel) », ou nil sans coupure.
    public func gapLine(_ gaps: [RecordingGap]) -> String? {
        guard !gaps.isEmpty else { return nil }
        let total = gaps.reduce(0) { $0 + $1.duration }
        if gaps.count == 1, let gap = gaps.first {
            return "Écoute coupée \(format.duration(total)) (\(gap.cause.shortLabel))"
        }
        return "Écoute coupée \(gaps.count) fois, \(format.duration(total)) en tout"
    }

    /// « dim. » et « 22 » pour la colonne de gauche.
    public func rowDay(_ session: SleepSession) -> (weekday: String, number: String) {
        let day = displayDay(of: session)
        let text = format.weekdayAndDay(day).split(separator: " ")
        return (String(text.first ?? ""), String(text.last ?? ""))
    }

    // MARK: - Calendrier

    /// « Novembre 2026 »
    public func monthTitle(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = format.locale
        formatter.calendar = nightCalendar.calendar
        formatter.timeZone = nightCalendar.calendar.timeZone
        formatter.dateFormat = "LLLL yyyy"
        let text = formatter.string(from: month)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Premier jour du mois qui contient `date`.
    public func month(containing date: Date) -> Date {
        weekCalendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    /// Les jours affichés pour un mois : semaines complètes, du lundi au dimanche.
    public func days(ofMonth month: Date, sessions: [SleepSession], now: Date) -> [JournalDay] {
        let calendar = weekCalendar
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: month),
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start),
            let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
            let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay)
        else { return [] }
        var byDay: [Date: [SleepSession]] = [:]
        for session in sessions {
            byDay[calendar.startOfDay(for: displayDay(of: session)), default: []].append(session)
        }
        let today = calendar.startOfDay(for: now)
        var days: [JournalDay] = []
        var day = firstWeek.start
        while day < lastWeek.end {
            days.append(JournalDay(
                date: day,
                dayNumber: calendar.component(.day, from: day),
                isInMonth: day >= monthInterval.start && day < monthInterval.end,
                isToday: day == today,
                isFuture: day > today,
                sessions: (byDay[day] ?? []).sorted { $0.referenceDate > $1.referenceDate }
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    // MARK: - Saisie à la main

    /// Horaires d'une session saisie : le coucher se place sur la soirée choisie
    /// (ou le jour même pour une sieste), puis chaque heure après la précédente.
    public func manualTimes(kind: SessionKind, day: Date, bedtime: ClockTime, sleepOnset: ClockTime?, wake: ClockTime, getUp: ClockTime?) -> SessionTimes {
        let calendar = nightCalendar.calendar
        let startOfDay = calendar.startOfDay(for: day)
        let anchor = kind == .night ? startOfDay.addingTimeInterval(12 * 3_600) : startOfDay
        func next(_ time: ClockTime, onOrAfter date: Date) -> Date {
            calendar.nextDate(
                after: date.addingTimeInterval(-1),
                matching: DateComponents(hour: time.hour, minute: time.minute, second: 0),
                matchingPolicy: .nextTime
            ) ?? date
        }
        let bed = next(bedtime, onOrAfter: anchor)
        let onset = sleepOnset.map { next($0, onOrAfter: bed) }
        let woke = next(wake, onOrAfter: onset ?? bed)
        let up = getUp.map { next($0, onOrAfter: woke) }
        return SessionTimes(bedtime: bed, sleepOnset: onset, wake: woke, getUp: up)
    }
}

extension RecordingGap.Cause {
    /// « appel », « Siri »… pour les listes.
    public var shortLabel: String {
        switch self {
        case .phoneCall: "appel"
        case .siri: "Siri"
        case .otherAudio: "autre app audio"
        case .systemStop: "arrêt par iOS"
        case .microphoneUnavailable: "micro indisponible"
        case .lowBattery: "batterie faible"
        case .appTerminated: "app fermée"
        case .unknown: "cause inconnue"
        }
    }
}

extension WakeFeeling {
    /// « Très mal », « Mal », « Moyen », « Bien », « Très bien ».
    public static func moodLabel(_ level: Int) -> String {
        ["Très mal", "Mal", "Moyen", "Bien", "Très bien"][min(5, max(1, level)) - 1]
    }
}

extension SleepSession {
    /// Part du temps au lit passée à dormir.
    public var efficiency: Double? {
        guard let asleep = asleepDuration, let inBed = timeInBed, inBed > 0 else { return nil }
        return min(1, asleep / inBed)
    }

    /// Temps réellement écouté : du début de la session à son arrêt (ou à `now`), moins les trous.
    public func listenedDuration(gaps: [RecordingGap], cut: ListeningCut? = nil, until now: Date) -> TimeInterval {
        guard recordingMode != .off, let start = detected.bedtime else { return 0 }
        // L'écoute s'arrête au lever (arrêt de la session) ; le réveil estimé peut être plus tôt.
        let end = state == .running ? now : (detected.getUp ?? detected.wake ?? now)
        guard end > start else { return 0 }
        let missing = gaps.reduce(0) { total, gap in
            total + max(0, min(gap.end, end).timeIntervalSince(max(gap.start, start)))
        }
        let ongoing = cut.map { max(0, end.timeIntervalSince(max($0.start, start))) } ?? 0
        return max(0, end.timeIntervalSince(start) - missing - ongoing)
    }
}
