import Foundation
import Observation
import SleepDomain

/// Modèle de vue de la fiche de nuit (maquette E21) : horaires, durées, écoute, ressenti et journal du soir.
/// Le score, les phases, les événements et la comparaison s'ajouteront avec les lots 3, 4 et 6.
@MainActor
@Observable
final class NightDetailViewModel {
    private(set) var session: SleepSession? = nil
    private(set) var gaps: [RecordingGap] = []
    private(set) var recordedBytes: Int64 = 0
    private(set) var events: [NightEvent] = []
    private(set) var eveningLog: EveningLog? = nil
    private(set) var olderID: UUID? = nil
    private(set) var newerID: UUID? = nil
    private(set) var isMissing = false
    private(set) var errorMessage: String? = nil
    private(set) var currentID: UUID

    let dependencies: JournalDependencies
    let text: NightDetailText
    private let now: () -> Date
    private let onChange: () async -> Void

    init(sessionID: UUID, dependencies: JournalDependencies, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }, onChange: @escaping () async -> Void) {
        self.currentID = sessionID
        self.dependencies = dependencies
        self.text = NightDetailText(calendar: calendar)
        self.now = now
        self.onChange = onChange
    }

    func load() async {
        do {
            let all = try await dependencies.sessions.sessions(in: nil)
            guard let index = all.firstIndex(where: { $0.id == currentID }) else {
                session = nil
                isMissing = true
                return
            }
            let current = all[index]
            let loadedGaps = try await dependencies.recordings.gaps(sessionID: current.id)
            let segments = try await dependencies.recordings.segments(sessionID: current.id)
            let loadedEvents = try await dependencies.events.events(sessionID: current.id)
            var log: EveningLog? = nil
            if current.kind == .night {
                log = try await dependencies.eveningLogs.log(forDay: text.nightCalendar.evening(of: current))
            }
            session = current
            newerID = index > 0 ? all[index - 1].id : nil
            olderID = index + 1 < all.count ? all[index + 1].id : nil
            gaps = loadedGaps
            recordedBytes = segments.reduce(0) { $0 + $1.byteSize }
            events = loadedEvents
            eveningLog = log
            isMissing = false
            errorMessage = nil
        } catch {
            errorMessage = "Impossible de lire cette nuit : \(error.localizedDescription)"
        }
    }

    func show(_ id: UUID?) async {
        guard let id else { return }
        currentID = id
        await load()
    }

    /// Après une modification : la fiche et le journal se mettent à jour.
    func didChange() async {
        await load()
        await onChange()
    }

    var isRunning: Bool {
        session?.state == .running
    }

    // MARK: - Textes

    var header: (title: String, subtitle: String) {
        session.map(text.header) ?? ("", "")
    }

    /// Les quatre horaires retenus.
    var times: [LabeledValue] {
        let retained = session?.times ?? SessionTimes()
        let nap = session?.kind == .nap
        return [
            LabeledValue(label: nap ? "Début" : "Coucher", value: clock(retained.bedtime)),
            LabeledValue(label: "Endormi", value: clock(retained.sleepOnset)),
            LabeledValue(label: "Réveil", value: clock(retained.wake)),
            LabeledValue(label: nap ? "Fin" : "Lever", value: clock(retained.getUp))
        ]
    }

    /// Sommeil, temps au lit, efficacité et réveils.
    var durations: [LabeledValue] {
        guard let session else { return [] }
        return [
            LabeledValue(label: "Sommeil", value: session.asleepDuration.map(text.format.duration) ?? "—"),
            LabeledValue(label: "Au lit", value: session.timeInBed.map(text.format.duration) ?? "—"),
            LabeledValue(label: "Efficacité", value: session.efficiency.map { "\(Int(($0 * 100).rounded())) %" } ?? "—"),
            LabeledValue(label: "Réveils", value: "\(session.significantWakeCount)")
        ]
    }

    var summary: String? {
        guard let session else { return nil }
        if session.state == .running {
            return "Nuit en cours : les durées seront connues à l’arrêt."
        }
        if session.state == .interrupted {
            let base = text.summary(session).map { $0 + " " } ?? ""
            return base + "L’app s’est arrêtée pendant la nuit : la fin est fixée à la dernière minute connue."
        }
        if session.times.sleepOnset == nil {
            return (text.summary(session).map { $0 + " " } ?? "") + "Heure d’endormissement inconnue : touche Modifier pour la préciser."
        }
        return text.summary(session)
    }

    var showsListening: Bool {
        guard let session else { return false }
        return session.recordingMode != .off || !gaps.isEmpty || recordedBytes > 0
    }

    var listeningLine: String {
        guard let session else { return "" }
        return text.listening(session, gaps: gaps, bytes: recordedBytes, now: now())
    }

    var gapLines: [String] {
        gaps.map(text.gap)
    }

    /// « Ronflements · 6 · 18 min », par type, dans l'ordre des types.
    var eventSummary: [LabeledValue] {
        let mine = events.filter { !$0.isSomeoneElse }
        return EventKind.allCases.compactMap { kind in
            let ofKind = mine.filter { $0.kind == kind }
            guard !ofKind.isEmpty else { return nil }
            let total = ofKind.reduce(0) { $0 + $1.duration }
            return LabeledValue(label: kind.pluralTitle, value: "\(ofKind.count) · \(ReplayText.duration(total))")
        }
    }

    /// La réécoute n'a de sens qu'une fois la nuit terminée, avec du son gardé.
    var canReplay: Bool {
        guard let session, session.state != .running else { return false }
        return recordedBytes > 0 || !events.isEmpty
    }

    /// Ressenti et journal du soir, seulement ce qui est renseigné.
    var feelingRows: [LabeledValue] {
        var rows: [LabeledValue] = []
        if let mood = session?.feeling?.mood {
            rows.append(LabeledValue(label: "Humeur au réveil", value: WakeFeeling.moodLabel(mood)))
        }
        if let energy = session?.feeling?.energy {
            rows.append(LabeledValue(label: "Énergie", value: "\(energy) sur 5"))
        }
        if let log = eveningLog {
            if let value = text.caffeine(log) { rows.append(LabeledValue(label: "Caféine", value: value)) }
            if let value = text.exercise(log) { rows.append(LabeledValue(label: "Sport", value: value)) }
            if let value = text.screens(log) { rows.append(LabeledValue(label: "Écrans", value: value)) }
            if let value = text.stress(log) { rows.append(LabeledValue(label: "Stress", value: value)) }
            if let value = text.meal(log) { rows.append(LabeledValue(label: "Repas", value: value)) }
        }
        return rows
    }

    var comment: String? {
        session?.comment
    }

    var eveningNote: String? {
        eveningLog?.note
    }

    var feelingTitle: String {
        session?.kind == .nap ? "Ressenti" : "Ressenti et journal du soir"
    }

    private func clock(_ date: Date?) -> String {
        date.map(text.format.clock) ?? "—"
    }
}

/// Un libellé et sa valeur, pour les grilles de la fiche.
struct LabeledValue: Identifiable, Hashable {
    let label: String
    let value: String

    var id: String { label }
}
