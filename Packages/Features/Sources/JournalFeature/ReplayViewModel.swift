import Foundation
import Observation
import SleepDomain

/// Textes courts de la réécoute.
enum ReplayText {
    /// « 6 s », « 2 min 10 », « 1 h 05 ».
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 {
            return "\(seconds) s"
        }
        if seconds < 3_600 {
            return String(format: "%d min %02d", seconds / 60, seconds % 60)
        }
        return String(format: "%d h %02d", seconds / 3_600, (seconds % 3_600) / 60)
    }

    /// Titre court d'un type pour les filtres.
    static func chipTitle(_ kind: EventKind) -> String {
        switch kind {
        case .snoring: "Ronflements"
        case .breathing: "Respirations"
        case .cough: "Toux"
        case .speech: "Paroles"
        case .movement: "Mouvements"
        case .awakening: "Réveils"
        case .external: "Bruits"
        case .unusual: "Inhabituels"
        }
    }
}

/// Modèle de vue de « Réécouter la nuit » (maquette E27).
@MainActor
@Observable
final class ReplayViewModel {
    let session: SleepSession
    private(set) var timeline: NightTimeline? = nil
    private(set) var state = ReplayState()
    var filter: EventKind? = nil
    private(set) var isLoading = true
    private(set) var isExporting = false
    var exportedURL: URL? = nil
    var errorMessage: String? = nil

    private let replayer: any NightReplaying
    private let events: any NightEventRepository
    private let format: SleepFormat
    private let nightCalendar: NightCalendar

    init(session: SleepSession, dependencies: JournalDependencies, calendar: Calendar = .current) {
        self.session = session
        self.replayer = dependencies.makeReplayer()
        self.events = dependencies.events
        self.format = SleepFormat(calendar: calendar)
        self.nightCalendar = NightCalendar(calendar: calendar)
    }

    /// Prépare la nuit, puis suit la lecture tant que l'écran est ouvert.
    func start() async {
        do {
            timeline = try await replayer.load(session)
        } catch {
            errorMessage = "La nuit n’a pas pu être préparée : \(error.localizedDescription)"
        }
        isLoading = false
        for await update in replayer.updates() {
            state = update
        }
    }

    func close() {
        replayer.stop()
    }

    // MARK: - Textes

    var title: String {
        nightCalendar.title(of: session)
    }

    var hasAudio: Bool {
        timeline?.hasAudio ?? false
    }

    /// « 03:14:05 »
    var clockText: String {
        guard let timeline else { return "--:--:--" }
        let date = timeline.date(at: state.position)
        let parts = format.calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    var currentEvent: NightEvent? {
        timeline?.event(at: state.position)
    }

    var currentTitle: String {
        if let event = currentEvent {
            return event.kind.title
        }
        if let timeline, timeline.gaps.contains(where: { $0.start <= timeline.date(at: state.position) && timeline.date(at: state.position) <= $0.end }) {
            return "Écoute coupée"
        }
        return "Calme"
    }

    var currentMeta: String? {
        currentEvent.map(meta)
    }

    func meta(_ event: NightEvent) -> String {
        "\(ReplayText.duration(event.duration)) · confiance \(event.confidenceLevel.title)"
    }

    func clock(_ event: NightEvent) -> String {
        format.clock(event.start)
    }

    var visibleEvents: [NightEvent] {
        (timeline?.events ?? []).filter { event in filter.map { event.kind == $0 } ?? true }
    }

    /// Filtres : « Tous 11 », puis chaque type présent avec son nombre.
    var chips: [(kind: EventKind?, label: String)] {
        let all = timeline?.events ?? []
        var chips: [(kind: EventKind?, label: String)] = [(nil, "Tous \(all.count)")]
        for kind in EventKind.allCases {
            let count = all.filter { $0.kind == kind }.count
            if count > 0 {
                chips.append((kind, "\(ReplayText.chipTitle(kind)) \(count)"))
            }
        }
        return chips
    }

    /// Repères d'heure sous la frise : toutes les 2 heures (toutes les heures pour une nuit courte).
    var ticks: [(label: String, fraction: Double)] {
        guard let timeline, timeline.duration > 0 else { return [] }
        let step: TimeInterval = timeline.duration > 4 * 3_600 ? 7_200 : 3_600
        let calendar = format.calendar
        var hour = calendar.dateInterval(of: .hour, for: timeline.start)?.end ?? timeline.start
        var ticks: [(label: String, fraction: Double)] = []
        while hour < timeline.date(at: timeline.duration) {
            let fraction = timeline.offset(of: hour) / timeline.duration
            let hourNumber = calendar.component(.hour, from: hour)
            if step == 3_600 || hourNumber % 2 == 0, fraction > 0.04, fraction < 0.96 {
                ticks.append((format.clock(hour), fraction))
            }
            hour = hour.addingTimeInterval(3_600)
        }
        return ticks
    }

    var rateLabel: String {
        switch state.rate {
        case 1.5: "1,5×"
        case 2: "2×"
        case 0.5: "0,5×"
        default: "1×"
        }
    }

    var isCurrentFavorite: Bool {
        currentEvent?.isFavorite ?? false
    }

    // MARK: - Commandes

    func togglePlay() {
        if state.isPlaying {
            replayer.pause()
        } else {
            replayer.play()
        }
    }

    func jump(by seconds: TimeInterval) {
        replayer.seek(to: state.position + seconds)
    }

    func seek(toFraction fraction: Double) {
        guard let timeline else { return }
        replayer.seek(to: min(1, max(0, fraction)) * timeline.duration)
    }

    func select(_ event: NightEvent) {
        guard let timeline else { return }
        // Deux secondes avant le début, pour entendre le son arriver.
        replayer.seek(to: max(0, timeline.offset(of: event.start) - 2))
        if !state.isPlaying {
            replayer.play()
        }
    }

    var hasPrevious: Bool {
        timeline?.previousEvent(before: state.position, kinds: filterKinds) != nil
    }

    var hasNext: Bool {
        timeline?.nextEvent(after: state.position, kinds: filterKinds) != nil
    }

    func previous() {
        if let event = timeline?.previousEvent(before: state.position, kinds: filterKinds) {
            select(event)
        }
    }

    func next() {
        if let event = timeline?.nextEvent(after: state.position, kinds: filterKinds) {
            select(event)
        }
    }

    private var filterKinds: Set<EventKind>? {
        filter.map { [$0] }
    }

    func cycleRate() {
        let rates = ReplayState.rates
        let index = rates.firstIndex(of: state.rate) ?? 0
        replayer.setRate(rates[(index + 1) % rates.count])
    }

    func toggleSkip() {
        replayer.setSkipsSilences(!state.skipsSilences)
    }

    /// Favori sur l'événement en cours : son passage est protégé du nettoyage.
    func toggleFavorite() async {
        guard var event = currentEvent, var timeline else { return }
        event.isFavorite.toggle()
        do {
            try await events.save([event])
            if let index = timeline.events.firstIndex(where: { $0.id == event.id }) {
                timeline.events[index] = event
                self.timeline = timeline
            }
        } catch {
            errorMessage = "Le favori n’a pas pu être enregistré : \(error.localizedDescription)"
        }
    }

    func export() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            exportedURL = try await replayer.exportPassage(around: state.position)
        } catch {
            errorMessage = "Le passage n’a pas pu être exporté : \(error.localizedDescription)"
        }
    }
}
