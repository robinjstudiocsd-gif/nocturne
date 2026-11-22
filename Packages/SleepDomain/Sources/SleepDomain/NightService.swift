import Foundation

/// État de l'écoute de la nuit, tel que l'interface l'affiche.
public struct NightStatus: Equatable, Sendable {
    public var session: SleepSession?
    public var isListening: Bool
    public var mode: RecordingMode
    public var segmentCount: Int
    public var recordedBytes: Int64
    public var currentLevelDb: Float?
    /// Vrai quand l'écoute est coupée et que la reprise automatique a échoué.
    public var needsResume: Bool
    public var gaps: [RecordingGap]
    public var liveActivityEnabled: Bool

    public init(
        session: SleepSession? = nil,
        isListening: Bool = false,
        mode: RecordingMode = .continuous,
        segmentCount: Int = 0,
        recordedBytes: Int64 = 0,
        currentLevelDb: Float? = nil,
        needsResume: Bool = false,
        gaps: [RecordingGap] = [],
        liveActivityEnabled: Bool = false
    ) {
        self.session = session
        self.isListening = isListening
        self.mode = mode
        self.segmentCount = segmentCount
        self.recordedBytes = recordedBytes
        self.currentLevelDb = currentLevelDb
        self.needsResume = needsResume
        self.gaps = gaps
        self.liveActivityEnabled = liveActivityEnabled
    }

    public static let idle = NightStatus()

    public var isRunning: Bool {
        session?.state == .running
    }
}

/// Service de la nuit : démarrer, arrêter, reprendre l'écoute.
public protocol NightRecordingService: Sendable {
    func start(kind: SessionKind, mode: RecordingMode, alarm: Date?) async throws -> SleepSession
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
