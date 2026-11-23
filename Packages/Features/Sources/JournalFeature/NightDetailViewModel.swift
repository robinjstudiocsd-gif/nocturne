import Foundation
import Observation
import SleepAnalysis
import SleepDomain

/// Modèle de vue de la fiche de nuit (maquette E21) : score, horaires, durées, profil de la nuit, écoute,
/// ressenti, journal du soir et comparaison. Les phases et le cœur de la montre s'ajouteront au lot 6.
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
    /// Score, qualité et comparaison ; rien pendant une nuit en cours.
    private(set) var report: NightReport? = nil
    /// Profil calme, agité ou éveil probable, relu depuis les fichiers de la nuit.
    private(set) var profile: NightProfile? = nil

    let dependencies: JournalDependencies
    let text: NightDetailText
    private let calendar: Calendar
    private let now: () -> Date
    private let onChange: () async -> Void

    init(sessionID: UUID, dependencies: JournalDependencies, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }, onChange: @escaping () async -> Void) {
        self.currentID = sessionID
        self.dependencies = dependencies
        self.text = NightDetailText(calendar: calendar)
        self.calendar = calendar
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
            report = current.state == .running
                ? nil
                : NightReporter(calendar: calendar).report(for: current, among: all, goals: dependencies.goals())
            isMissing = false
            errorMessage = nil
            let loadedProfile = await dependencies.profiles.profile(for: current)
            if currentID == current.id {
                profile = loadedProfile
            }
        } catch {
            errorMessage = "Impossible de lire cette nuit : \(error.localizedDescription)"
        }
    }

    func show(_ id: UUID?) async {
        guard let id else { return }
        currentID = id
        profile = nil
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

    // MARK: - Score

    var scoreValue: Int? {
        report?.score.total
    }

    var scoreIsApproximate: Bool {
        report?.score.isApproximate ?? false
    }

    /// « Qualité estimée : très bonne »
    var qualityLine: String {
        if session?.state == .running {
            return "Nuit en cours"
        }
        if let quality = report?.quality {
            return "Qualité estimée : \(quality.title)"
        }
        return "Score indisponible"
    }

    /// Fiabilité et origine des données : « Fiabilité moyenne », « iPhone seul ».
    var chips: [String] {
        guard let session, let report else { return [] }
        return [report.reliabilityText, Self.sourceText(session)]
    }

    static func sourceText(_ session: SleepSession) -> String {
        switch session.primarySource {
        case .watch:
            return "Apple Watch + iPhone"
        case .motion, .microphone:
            return "iPhone seul"
        case .manual:
            if session.state == .manual {
                return "Saisie manuelle"
            }
            return session.recordingMode == .off ? "Micro coupé" : "iPhone seul"
        }
    }

    // MARK: - Profil de la nuit

    var showsProfile: Bool {
        profile?.states.contains { $0 != .unknown } == true
    }

    /// Plages du profil : ligne 0 éveil probable, 1 agité, 2 calme ; fractions de la nuit.
    var profileBands: [(start: Double, end: Double, row: Int)] {
        guard let profile else { return [] }
        let total = profile.end.timeIntervalSince(profile.start)
        guard total > 0 else { return [] }
        return profile.intervals.compactMap { interval in
            guard let row = Self.profileRow(interval.state) else { return nil }
            return (
                start: interval.start.timeIntervalSince(profile.start) / total,
                end: interval.end.timeIntervalSince(profile.start) / total,
                row: row
            )
        }
    }

    static func profileRow(_ state: EpochState) -> Int? {
        switch state {
        case .awake: 0
        case .agitated: 1
        case .calm: 2
        case .unknown: nil
        }
    }

    var profileTicks: [HourTick] {
        guard let profile else { return [] }
        return text.format.hourTicks(from: profile.start, to: profile.end)
    }

    /// Durée de chaque état, dans l'ordre éveil probable, agité, calme.
    var profileDurations: [(title: String, value: String)] {
        guard let profile else { return [] }
        return [EpochState.awake, .agitated, .calm].map { state in
            (title: state.title, value: text.format.duration(profile.duration(of: state)))
        }
    }

    var profileAccessibility: String {
        "Profil : " + profileDurations.map { "\($0.title.lowercased()) \($0.value)" }.joined(separator: ", ")
    }

    // MARK: - Comparaison

    var showsComparison: Bool {
        guard let session, session.kind == .night, let report else { return false }
        return report.previousNights > 0 && !comparisonRows.isEmpty
    }

    var comparisonSubtitle: String {
        let count = report?.previousNights ?? 0
        return count == 1 ? "Par rapport à ta nuit précédente" : "Par rapport à ta moyenne sur \(count) nuits"
    }

    /// Durée, coucher et score, comparés à la moyenne des nuits précédentes.
    var comparisonRows: [ComparisonRow] {
        guard let session, let report else { return [] }
        let format = text.format
        var rows: [ComparisonRow] = []
        if let asleep = session.asleepDuration, let average = report.averages.asleep, let difference = report.comparison.asleep {
            rows.append(ComparisonRow(
                label: "Durée",
                detail: "\(format.duration(asleep)) · moy. \(format.duration(average))",
                difference: DifferenceText.duration(difference, format: format)
            ))
        }
        if let bedtime = session.times.bedtime, let average = report.averages.bedtime, let difference = report.comparison.bedtime {
            rows.append(ComparisonRow(
                label: "Coucher",
                detail: "\(format.clock(bedtime)) · moy. \(String(format: "%02d:%02d", average.hour, average.minute))",
                difference: DifferenceText.duration(difference, format: format)
            ))
        }
        if let score = report.score.total, let average = report.averageScore {
            rows.append(ComparisonRow(
                label: "Score",
                detail: "\(report.score.displayText) · moy. \(Int(average.rounded()))",
                difference: DifferenceText.points(Double(score) - average)
            ))
        }
        return rows
    }
}

/// Une ligne de la comparaison : « Durée · 7 h 51 · moy. 7 h 11 · +40 min ».
struct ComparisonRow: Identifiable, Hashable {
    let label: String
    let detail: String
    let difference: String

    var id: String { label }
}

/// Un libellé et sa valeur, pour les grilles de la fiche.
struct LabeledValue: Identifiable, Hashable {
    let label: String
    let value: String

    var id: String { label }
}
