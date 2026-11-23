import Foundation

/// Coupure de l'écoute encore en cours : depuis quand, et pourquoi.
public struct ListeningCut: Equatable, Sendable {
    public var start: Date
    public var cause: RecordingGap.Cause

    public init(start: Date, cause: RecordingGap.Cause) {
        self.start = start
        self.cause = cause
    }
}

/// État de l'écoute de la nuit, tel que l'interface l'affiche.
public struct NightStatus: Equatable, Sendable {
    public var session: SleepSession?
    public var isListening: Bool
    public var mode: RecordingMode
    public var segmentCount: Int
    public var recordedBytes: Int64
    /// Événements sonores repérés depuis le début de la session.
    public var eventCount: Int
    public var currentLevelDb: Float?
    /// Vrai quand l'écoute est coupée et que la reprise automatique a échoué.
    public var needsResume: Bool
    /// Trous terminés de la nuit.
    public var gaps: [RecordingGap]
    /// Coupure en cours, pas encore refermée.
    public var cut: ListeningCut?
    public var alarm: NightAlarm?
    public var liveActivityEnabled: Bool

    public init(
        session: SleepSession? = nil,
        isListening: Bool = false,
        mode: RecordingMode = .continuous,
        segmentCount: Int = 0,
        recordedBytes: Int64 = 0,
        eventCount: Int = 0,
        currentLevelDb: Float? = nil,
        needsResume: Bool = false,
        gaps: [RecordingGap] = [],
        cut: ListeningCut? = nil,
        alarm: NightAlarm? = nil,
        liveActivityEnabled: Bool = false
    ) {
        self.session = session
        self.isListening = isListening
        self.mode = mode
        self.segmentCount = segmentCount
        self.recordedBytes = recordedBytes
        self.eventCount = eventCount
        self.currentLevelDb = currentLevelDb
        self.needsResume = needsResume
        self.gaps = gaps
        self.cut = cut
        self.alarm = alarm
        self.liveActivityEnabled = liveActivityEnabled
    }

    public static let idle = NightStatus()

    public var isRunning: Bool {
        session?.state == .running
    }

    /// Temps réellement écouté : du début de la session à `now` (ou à son arrêt), moins les trous et la coupure en cours.
    public func listenedDuration(until now: Date) -> TimeInterval {
        guard mode != .off, let session else { return 0 }
        return session.listenedDuration(gaps: gaps, cut: cut, until: now)
    }
}

/// Service de la nuit : démarrer, arrêter, reprendre l'écoute.
public protocol NightRecordingService: Sendable {
    func start(kind: SessionKind, mode: RecordingMode, alarm: NightAlarm?) async throws -> SleepSession
    @discardableResult
    func stop() async throws -> SleepSession?
    func resume() async
    func currentStatus() async -> NightStatus
    func statusUpdates() async -> AsyncStream<NightStatus>
    /// Au lancement : reprend ou termine une nuit interrompue (app fermée, batterie vide).
    func recoverIfNeeded() async
}

/// Données de la Live Activity « Nuit en cours ».
/// La conformité à ActivityKit est déclarée dans l'app et dans l'extension, pas ici.
public struct NightActivityAttributes: Codable, Hashable, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var isListening: Bool
        public var alarmDate: Date?
        public var isRinging: Bool

        public init(isListening: Bool, alarmDate: Date?, isRinging: Bool) {
            self.isListening = isListening
            self.alarmDate = alarmDate
            self.isRinging = isRinging
        }
    }

    public var startDate: Date
    public var kind: SessionKind

    public init(startDate: Date, kind: SessionKind) {
        self.startDate = startDate
        self.kind = kind
    }
}
