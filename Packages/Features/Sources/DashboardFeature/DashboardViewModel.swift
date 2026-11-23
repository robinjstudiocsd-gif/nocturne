import Foundation
import Observation
import SleepAnalysis
import SleepDomain

/// Ce dont l'accueil a besoin : les nuits, leurs sons, leur profil, et les réglages du score.
public struct DashboardDependencies: Sendable {
    public let sessions: any SleepSessionRepository
    public let events: any NightEventRepository
    public let profiles: any NightProfileProviding
    /// Besoin de sommeil par nuit, pour la dette.
    public let sleepNeed: @Sendable () -> TimeInterval
    public let goals: @Sendable () -> ScoreGoals

    public init(
        sessions: any SleepSessionRepository,
        events: any NightEventRepository,
        profiles: any NightProfileProviding,
        sleepNeed: @escaping @Sendable () -> TimeInterval,
        goals: @escaping @Sendable () -> ScoreGoals = { ScoreGoals() }
    ) {
        self.sessions = sessions
        self.events = events
        self.profiles = profiles
        self.sleepNeed = sleepNeed
        self.goals = goals
    }
}

/// Une barre du graphique « 7 dernières nuits » : la nuit qui se termine ce matin-là.
public struct WeekBar: Identifiable, Hashable, Sendable {
    public let day: Date
    /// « lun. »
    public let label: String
    public let asleep: TimeInterval?
    /// La dernière nuit, mise en avant.
    public let isLast: Bool

    public var id: Date { day }
}

/// Modèle de vue de l'accueil (maquette E10) : dernière nuit, dette de sommeil, régularité, 7 dernières nuits.
@MainActor
@Observable
public final class DashboardViewModel {
    public private(set) var lastNight: SleepSession? = nil
    public private(set) var report: NightReport? = nil
    public private(set) var profile: NightProfile? = nil
    public private(set) var events: [NightEvent] = []
    public private(set) var debt: SleepDebt? = nil
    public private(set) var regularity: TimeInterval? = nil
    public private(set) var week: [WeekBar] = []
    public private(set) var errorMessage: String? = nil
    public private(set) var isLoaded = false

    let dependencies: DashboardDependencies
    let format: SleepFormat
    private let calendar: Calendar
    private let nightCalendar: NightCalendar
    private let now: () -> Date

    public init(dependencies: DashboardDependencies, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.dependencies = dependencies
        self.format = SleepFormat(calendar: calendar)
        self.calendar = calendar
        self.nightCalendar = NightCalendar(calendar: calendar)
        self.now = now
    }

    public func load() async {
        do {
            let all = try await dependencies.sessions.sessions(in: nil)
            let nights = all
                .filter { $0.kind == .night && $0.state != .running }
                .sorted { $0.referenceDate > $1.referenceDate }
            let last = nights.first
            let goals = dependencies.goals()
            lastNight = last
            report = last.map { NightReporter(calendar: calendar).report(for: $0, among: all, goals: goals) }
            if let last {
                events = try await dependencies.events.events(sessionID: last.id)
            } else {
                events = []
            }
            debt = nights.isEmpty ? nil : SleepDebt.compute(sessions: all, need: dependencies.sleepNeed(), through: now(), days: 14, calendar: calendar)
            regularity = NightAverages(sessions: Array(nights.prefix(7)), calendar: calendar).regularity
            week = weekBars(nights: nights, last: last)
            errorMessage = nil
            isLoaded = true
            if let last {
                let loaded = await dependencies.profiles.profile(for: last)
                if lastNight?.id == last.id {
                    profile = loaded
                }
            } else {
                profile = nil
            }
        } catch {
            errorMessage = "Impossible de lire tes nuits : \(error.localizedDescription)"
        }
    }

    // MARK: - Dernière nuit

    /// « Samedi 21 → dimanche 22 novembre » (l'année seulement si ce n'est pas l'année en cours).
    var lastNightTitle: String {
        guard let lastNight else { return "" }
        let header = NightDetailText(calendar: calendar).header(lastNight)
        let year = String(calendar.component(.year, from: now()))
        var subtitle = header.subtitle
        if subtitle.hasSuffix(" " + year) {
            subtitle.removeLast(year.count + 1)
        }
        return header.title + " " + subtitle
    }

    var qualityLine: String {
        report?.quality.map { "Qualité estimée : \($0.title)" } ?? "Score indisponible"
    }

    var chips: [String] {
        guard let lastNight, let report else { return [] }
        return [report.reliabilityText, Self.sourceText(lastNight)]
    }

    static func sourceText(_ session: SleepSession) -> String {
        switch session.primarySource {
        case .watch: return "Apple Watch + iPhone"
        case .motion, .microphone: return "iPhone seul"
        case .manual:
            if session.state == .manual {
                return "Saisie manuelle"
            }
            return session.recordingMode == .off ? "Micro coupé" : "iPhone seul"
        }
    }

    /// Sommeil, au lit, endormissement, réveils, coucher, lever.
    var values: [DashboardValue] {
        guard let night = lastNight else { return [] }
        let times = night.times
        return [
            DashboardValue(label: "Sommeil", value: night.asleepDuration.map(format.duration) ?? "—"),
            DashboardValue(label: "Au lit", value: night.timeInBed.map(format.duration) ?? "—"),
            DashboardValue(label: "Endormissement", value: night.sleepLatency.map(format.duration) ?? "—"),
            DashboardValue(label: "Réveils", value: "\(night.significantWakeCount)"),
            DashboardValue(label: "Coucher", value: times.bedtime.map(format.clock) ?? "—"),
            DashboardValue(label: "Lever", value: times.getUp.map(format.clock) ?? "—")
        ]
    }

    var showsProfile: Bool {
        profile?.states.contains { $0 != .unknown } == true
    }

    /// Plages du profil : ligne 0 éveil probable, 1 agité, 2 calme ; fractions de la nuit.
    var profileBands: [(start: Double, end: Double, row: Int)] {
        guard let profile else { return [] }
        let total = profile.end.timeIntervalSince(profile.start)
        guard total > 0 else { return [] }
        return profile.intervals.compactMap { interval in
            let row: Int
            switch interval.state {
            case .awake: row = 0
            case .agitated: row = 1
            case .calm: row = 2
            case .unknown: return nil
            }
            return (
                start: interval.start.timeIntervalSince(profile.start) / total,
                end: interval.end.timeIntervalSince(profile.start) / total,
                row: row
            )
        }
    }

    var profileTicks: [HourTick] {
        guard let profile else { return [] }
        return format.hourTicks(from: profile.start, to: profile.end)
    }

    var profileDurations: [(title: String, value: String)] {
        guard let profile else { return [] }
        return [EpochState.awake, .agitated, .calm].map { state in
            (title: state.title, value: format.duration(profile.duration(of: state)))
        }
    }

    var profileAccessibility: String {
        "Profil : " + profileDurations.map { "\($0.title.lowercased()) \($0.value)" }.joined(separator: ", ")
    }

    /// « 11 événements sonores »
    var eventsTitle: String? {
        guard lastNight?.recordingMode != .off else { return nil }
        let count = events.filter { !$0.isSomeoneElse }.count
        switch count {
        case 0: return "Aucun événement sonore"
        case 1: return "1 événement sonore"
        default: return "\(count) événements sonores"
        }
    }

    /// « 6 ronflements (18 min), 1 parole, 4 bruits extérieurs »
    var eventsDetail: String? {
        let mine = events.filter { !$0.isSomeoneElse }
        let parts = EventKind.allCases.compactMap { kind -> String? in
            let ofKind = mine.filter { $0.kind == kind }
            guard !ofKind.isEmpty else { return nil }
            let name = ofKind.count > 1 ? kind.pluralTitle.lowercased() : Self.singular(kind)
            var text = "\(ofKind.count) \(name)"
            if kind == .snoring {
                text += " (\(format.duration(ofKind.reduce(0) { $0 + $1.duration })))"
            }
            return text
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func singular(_ kind: EventKind) -> String {
        kind == .speech ? "parole" : kind.title.lowercased()
    }

    var canReplay: Bool {
        guard let lastNight else { return false }
        return lastNight.recordingMode != .off && !(lastNight.recordingMode == .events && events.isEmpty)
    }

    var scoreInsight: String? {
        guard let report, let lastNight else { return nil }
        return NightInsight.scoreLine(report: report, session: lastNight, goals: dependencies.goals(), format: format)
    }

    // MARK: - Dette et régularité

    var debtValue: String {
        debt.map { format.duration($0.total) } ?? "—"
    }

    var debtDetail: String {
        "sur 14 nuits, pour un besoin de \(format.duration(dependencies.sleepNeed())) par nuit"
    }

    var regularityValue: String {
        regularity.map { "± \(format.duration($0))" } ?? "—"
    }

    var regularityDetail: String {
        regularity == nil ? "dès 3 nuits enregistrées" : "d’écart moyen du milieu de nuit, sur 7 nuits"
    }

    // MARK: - 7 dernières nuits

    private func weekBars(nights: [SleepSession], last: SleepSession?) -> [WeekBar] {
        let today = calendar.startOfDay(for: now())
        var byMorning: [Date: SleepSession] = [:]
        for night in nights {
            let morning = calendar.startOfDay(for: nightCalendar.morning(of: night))
            if byMorning[morning] == nil {
                byMorning[morning] = night
            }
        }
        return (0..<7).reversed().compactMap { offset -> WeekBar? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let night = byMorning[day]
            return WeekBar(
                day: day,
                label: format.shortWeekday(day),
                asleep: night?.asleepDuration,
                isLast: night != nil && night?.id == last?.id
            )
        }
    }

    var weekAverage: TimeInterval? {
        let values = week.compactMap(\.asleep)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    var weekAverageText: String? {
        weekAverage.map { "moyenne \(format.duration($0))" }
    }

    var objective: TimeInterval {
        dependencies.goals().duration.lowerBound
    }

    var comparisonLine: String? {
        report.flatMap { NightInsight.comparisonLine($0.comparison, format: format) }
    }

    /// « Au moins 7 h de sommeil · 4 nuits sur 7 »
    var durationObjective: (title: String, count: Int, total: Int) {
        let reached = week.filter { ($0.asleep ?? 0) >= objective }.count
        return (title: "Au moins \(format.duration(objective)) de sommeil", count: reached, total: week.count)
    }

    var weekAccessibility: String {
        let values = week.compactMap(\.asleep)
        guard let shortest = values.min(), let longest = values.max() else { return "Aucune nuit mesurée ces 7 derniers jours" }
        let above = values.filter { $0 >= objective }.count
        return "Durée de sommeil des 7 dernières nuits : de \(format.duration(shortest)) à \(format.duration(longest)), dont \(above) nuit\(above > 1 ? "s" : "") au-dessus de \(format.duration(objective))"
    }
}

/// Une valeur de la dernière nuit (« Sommeil · 7 h 51 »).
struct DashboardValue: Identifiable, Hashable {
    let label: String
    let value: String

    var id: String { label }
}
