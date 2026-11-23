import Foundation
import Observation
import SleepDomain

/// Modèle de vue de la nuit : préparer la session, suivre l'écoute, puis afficher « Bonjour ».
@MainActor
@Observable
public final class NightViewModel {
    /// La sonnerie jouée par l'app arrive au lot 5 : d'ici là, les textes le disent clairement.
    static let alarmsRing = false

    /// Réglages de « Préparer ma nuit », gardés d'un soir à l'autre.
    public var plan: NightPlan {
        get { currentPlan }
        set {
            guard newValue != currentPlan else { return }
            currentPlan = newValue
            preferences.nightPlan = newValue
            refreshChecksSoon()
        }
    }
    private var currentPlan: NightPlan
    public private(set) var checks: [PreflightItem] = []
    private var lastReadings: PreflightReadings? = nil
    public private(set) var status: NightStatus = .idle
    public private(set) var isStarting = false
    public private(set) var isStopping = false
    /// Écran « Bonjour » à afficher après la nuit.
    public private(set) var morning: MorningViewModel? = nil
    public var alertMessage: String? = nil

    public let quality: AudioQuality
    public let eveningLogs: any EveningLogRepository
    let format: SleepFormat
    let nightCalendar: NightCalendar

    private let service: any NightRecordingService
    private let preflight: any PreflightProvider
    private let preferences: any NightPreferencesStore
    private let lifecycle: SessionLifecycle
    private let now: () -> Date
    @ObservationIgnored private var acknowledged: Set<UUID> = []
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    public init(
        service: any NightRecordingService,
        preflight: any PreflightProvider,
        preferences: any NightPreferencesStore,
        lifecycle: SessionLifecycle,
        eveningLogs: any EveningLogRepository,
        quality: AudioQuality = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.service = service
        self.preflight = preflight
        self.preferences = preferences
        self.lifecycle = lifecycle
        self.eveningLogs = eveningLogs
        self.quality = quality
        self.format = SleepFormat(calendar: calendar)
        self.nightCalendar = NightCalendar(calendar: calendar)
        self.now = now
        self.currentPlan = preferences.nightPlan
    }

    public var lighting: NightLighting {
        preferences.nightLighting
    }

    public var retentionNights: Int {
        preferences.audioRetentionNights
    }

    /// L'écran de nuit, puis « Bonjour », recouvrent toute l'app.
    public var isCoverPresented: Bool {
        status.isRunning || morning != nil || isStopping
    }

    // MARK: - Suivi de l'écoute

    /// Suit l'écoute tant que l'app est ouverte.
    public func observe() async {
        let updates = await service.statusUpdates()
        for await update in updates {
            apply(update)
        }
    }

    private func apply(_ update: NightStatus) {
        status = update
        // Nuit terminée au lancement après une fermeture de l'app : on propose « Bonjour » pour la corriger.
        guard
            morning == nil, !isStopping,
            let session = update.session, session.state == .interrupted,
            !acknowledged.contains(session.id)
        else { return }
        acknowledged.insert(session.id)
        morning = makeMorning(session: session, snapshot: update)
    }

    // MARK: - Vérifications

    /// Rafraîchit les vérifications toutes les 5 secondes tant que l'écran est affiché.
    public func watchChecks() async {
        while !Task.isCancelled {
            await refreshChecks()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    public func refreshChecks() async {
        let readings = await preflight.readings()
        lastReadings = readings
        let moment = now()
        checks = Preflight.evaluate(
            readings,
            kind: plan.kind,
            mode: plan.mode,
            quality: quality,
            alarm: plan.alarm(startingAt: moment, calendar: format.calendar),
            now: moment,
            format: format
        )
    }

    private func refreshChecksSoon() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            await self?.refreshChecks()
        }
    }

    public var checksSummary: String {
        checks.isEmpty ? "" : Preflight.summary(checks)
    }

    /// Action proposée par une vérification. Renvoie vrai s'il faut ouvrir les Réglages de l'iPhone.
    public func perform(_ action: PreflightAction) async -> Bool {
        switch action {
        case .requestMicrophone:
            _ = await preflight.requestMicrophone()
        case .requestNotifications:
            _ = await preflight.requestNotifications()
        case .openSettings:
            return true
        }
        await refreshChecks()
        return false
    }

    // MARK: - Commencer, arrêter, reprendre

    public func start() async {
        guard !isStarting, !status.isRunning else { return }
        isStarting = true
        defer { isStarting = false }
        let moment = now()
        // Sous 1 Go libre, l'audio continu ne tiendrait pas : la nuit passe en mode événements.
        let mode = Preflight.effectiveMode(plan.mode, freeBytes: lastReadings?.freeBytes)
        do {
            _ = try await service.start(kind: plan.kind, mode: mode, alarm: plan.alarm(startingAt: moment, calendar: format.calendar))
            apply(await service.currentStatus())
        } catch {
            alertMessage = "La session n’a pas pu commencer. \(error.localizedDescription)"
        }
    }

    public func stop() async {
        guard !isStopping else { return }
        isStopping = true
        defer { isStopping = false }
        do {
            if let finished = try await service.stop() {
                acknowledged.insert(finished.id)
                morning = makeMorning(session: finished, snapshot: await service.currentStatus())
            }
        } catch {
            alertMessage = "La session n’a pas pu s’arrêter. \(error.localizedDescription)"
        }
    }

    public func resume() async {
        await service.resume()
    }

    /// « Bonjour » refermé, enregistré ou passé.
    public func finishMorning() {
        morning = nil
    }

    private func makeMorning(session: SleepSession, snapshot: NightStatus) -> MorningViewModel {
        MorningViewModel(session: session, snapshot: snapshot, lifecycle: lifecycle, calendar: format.calendar, now: now)
    }

    // MARK: - Textes de « Préparer ma nuit »

    public var dateLine: String {
        let moment = now()
        return format.dayTitle(plan.kind == .night ? nightCalendar.evening(at: moment) : moment)
    }

    public var alarmValue: String {
        guard plan.alarmEnabled, let date = plan.nextAlarmDate(after: now(), calendar: format.calendar) else { return "Aucun" }
        return format.weekdayAndClock(date)
    }

    public var smartWakeSubtitle: String {
        let date = plan.nextAlarmDate(after: now(), calendar: format.calendar) ?? now()
        let start = date.addingTimeInterval(-TimeInterval(plan.smartWindowMinutes * 60))
        return "Entre \(format.clock(start)) et \(format.clock(date)), en sommeil léger"
    }

    public var alarmNote: String {
        guard plan.alarmEnabled else {
            return "Aucun réveil prévu : la nuit s’arrêtera quand tu l’arrêteras."
        }
        guard Self.alarmsRing else {
            return "Le réveil ne sonne pas encore : il arrive avec le lot 5. D’ici là, garde une alarme dans l’app Horloge."
        }
        return "Sous iOS 18, l’app joue elle-même l’alarme : ne la ferme pas d’un balayage. Une notification de secours est aussi programmée."
    }

    public var napValue: String {
        "\(plan.napMinutes) min"
    }

    public var napNote: String {
        guard Self.alarmsRing else {
            return "La fin de sieste ne sonne pas encore : elle arrive avec le lot 5. D’ici là, garde une alarme dans l’app Horloge."
        }
        return "Le réveil sonne au bout de \(plan.napMinutes) min. Pas de réveil intelligent pendant une sieste."
    }

    public var modeValue: String {
        NightText.modeTitle(plan.mode)
    }

    public var modeSubtitle: String {
        NightText.modeSubtitle(plan.mode, retention: retentionNights)
    }

    public var startTitle: String {
        plan.kind == .night ? "Commencer la nuit" : "Commencer la sieste"
    }

    // MARK: - Textes de « Nuit en cours »

    public var nightHeader: String {
        let title = status.session?.kind == .nap ? "Sieste en cours" : "Nuit en cours"
        return "\(title) · \(NightText.modeShort(status.mode))"
    }

    public func listeningLine(at moment: Date) -> String {
        guard status.mode != .off else { return "Seuls les horaires sont notés" }
        if let cut = status.cut {
            return "Écoute coupée depuis \(format.clock(cut.start))"
        }
        if status.needsResume {
            return "Écoute arrêtée"
        }
        let start = status.session?.detected.bedtime ?? moment
        return "Écoute depuis \(format.clock(start)) · \(format.duration(status.listenedDuration(until: moment))) enregistrées"
    }

    public func clock(at moment: Date) -> String {
        format.clock(moment)
    }

    public func day(at moment: Date) -> String {
        format.longDay(moment)
    }

    public func alarmLine(at moment: Date) -> String? {
        guard let alarm = status.alarm else { return nil }
        let clock = format.clock(alarm.date)
        guard alarm.date > moment else { return "Réveil prévu à \(clock)" }
        return "Réveil \(clock) · dans \(format.duration(alarm.date.timeIntervalSince(moment)))"
    }

    public var alarmDetailLine: String? {
        guard let alarm = status.alarm else { return nil }
        guard Self.alarmsRing else { return "Le réveil ne sonne pas encore (lot 5)" }
        return alarm.smartWindowStart.map { "Réveil intelligent dès \(format.clock($0))" }
    }

    /// Message de coupure, avec le bouton « Reprendre l'écoute ».
    public var cutMessage: String? {
        guard status.isRunning, status.mode != .off else { return nil }
        if let cut = status.cut {
            let first = NightText.cutSentence(cut.cause, at: format.clock(cut.start))
            let second = status.needsResume ? "La reprise automatique a échoué." : "Elle reprendra toute seule dès que possible."
            return "\(first) \(second)"
        }
        return status.needsResume ? "L’écoute n’a pas pu démarrer." : nil
    }

    public var lockHint: String {
        status.mode == .off
            ? "Tu peux verrouiller l’écran. Le matin, ouvre l’app pour arrêter la nuit."
            : "Tu peux verrouiller l’écran : l’écoute continue."
    }

    public var stopTitle: String {
        status.session?.kind == .nap ? "Arrêter la sieste" : "Arrêter la nuit"
    }
}
