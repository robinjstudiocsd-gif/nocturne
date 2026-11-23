import Foundation
import Observation
import SleepDomain

/// Ce dont le Journal a besoin : les nuits, leur écoute, les journaux du soir et les cas d'usage.
public struct JournalDependencies: Sendable {
    public let sessions: any SleepSessionRepository
    public let recordings: any RecordingRepository
    public let eveningLogs: any EveningLogRepository
    public let lifecycle: SessionLifecycle
    public let eraser: any SessionDataEraser

    public init(
        sessions: any SleepSessionRepository,
        recordings: any RecordingRepository,
        eveningLogs: any EveningLogRepository,
        lifecycle: SessionLifecycle,
        eraser: any SessionDataEraser
    ) {
        self.sessions = sessions
        self.recordings = recordings
        self.eveningLogs = eveningLogs
        self.lifecycle = lifecycle
        self.eraser = eraser
    }
}

/// Ouvre la fiche d'une nuit dans la pile de navigation du Journal.
public struct NightRoute: Hashable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

/// Modèle de vue du Journal (maquette E20) : liste par semaine ou calendrier, filtre et recherche.
@MainActor
@Observable
public final class JournalViewModel {
    public enum Display: Sendable {
        case list
        case calendar
    }

    public private(set) var sessions: [SleepSession] = []
    public private(set) var gapsBySession: [UUID: [RecordingGap]] = [:]
    public private(set) var isLoading = false
    public private(set) var errorMessage: String? = nil
    public var filter: JournalFilter = .all
    public var searchText = ""
    public var display: Display = .list
    public private(set) var month: Date

    public let dependencies: JournalDependencies
    let organizer: JournalOrganizer
    let calendar: Calendar
    private let now: () -> Date

    public init(dependencies: JournalDependencies, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.dependencies = dependencies
        self.calendar = calendar
        self.organizer = JournalOrganizer(calendar: calendar)
        self.now = now
        self.month = JournalOrganizer(calendar: calendar).month(containing: now())
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await dependencies.sessions.sessions(in: nil)
            let gaps = try await dependencies.recordings.allGaps()
            sessions = loaded
            gapsBySession = Dictionary(grouping: gaps, by: \.sessionID)
            errorMessage = nil
        } catch {
            errorMessage = "Impossible de lire tes nuits : \(error.localizedDescription)"
        }
    }

    /// Les sessions après filtre et recherche.
    var visibleSessions: [SleepSession] {
        sessions.filter { filter.includes($0) && organizer.matches($0, query: searchText) }
    }

    var weeks: [JournalWeek] {
        organizer.weeks(visibleSessions, now: now())
    }

    var days: [JournalDay] {
        organizer.days(ofMonth: month, sessions: visibleSessions, now: now())
    }

    var monthTitle: String {
        organizer.monthTitle(month)
    }

    var canShowNextMonth: Bool {
        month < organizer.month(containing: now())
    }

    func showMonth(offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: month) else { return }
        month = organizer.month(containing: next)
    }

    func toggleDisplay() {
        display = display == .list ? .calendar : .list
    }

    func gaps(for session: SleepSession) -> [RecordingGap] {
        gapsBySession[session.id] ?? []
    }

    /// Durée affichée sous un jour du calendrier.
    func calendarValue(for day: JournalDay) -> String? {
        guard let session = day.sessions.first(where: { $0.kind == .night }) ?? day.sessions.first else { return nil }
        guard let duration = session.asleepDuration ?? session.timeInBed else { return "•" }
        return organizer.format.shortDuration(duration)
    }

    func accessibilityLabel(for day: JournalDay) -> String {
        var parts = ["\(day.dayNumber)"]
        if let value = calendarValue(for: day), value != "•" {
            parts.append(value)
        }
        if day.isToday {
            parts.append("aujourd’hui")
        }
        return parts.joined(separator: ", ")
    }

    func makeAddNight() -> AddNightViewModel {
        AddNightViewModel(lifecycle: dependencies.lifecycle, calendar: calendar, now: now())
    }
}
