import Foundation

/// Qualité de l'audio enregistré (étude, « Enregistrement audio »).
public enum AudioQuality: String, Codable, Sendable, CaseIterable {
    /// 16 kbit/s, réservé au mode économique.
    case economy
    /// 32 kbit/s à 24 kHz, par défaut.
    case standard
    /// 64 kbit/s à 44,1 kHz.
    case high

    public var sampleRate: Double {
        switch self {
        case .economy: 16_000
        case .standard: 24_000
        case .high: 44_100
        }
    }

    public var bitRate: Int {
        switch self {
        case .economy: 16_000
        case .standard: 32_000
        case .high: 64_000
        }
    }
}

/// Une tranche d'audio continu de 5 minutes au plus, rangée dans un fichier .m4a.
public struct AudioSegment: Identifiable, Hashable, Codable, Sendable {
    public enum State: String, Codable, Sendable {
        case recording
        case complete
        case truncated
    }

    public var id: UUID
    public var sessionID: UUID
    public var index: Int
    public var start: Date
    public var duration: TimeInterval
    /// Chemin relatif au dossier Application Support de l'app.
    public var relativePath: String
    public var byteSize: Int64
    public var quality: AudioQuality
    public var state: State

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        index: Int,
        start: Date,
        duration: TimeInterval,
        relativePath: String,
        byteSize: Int64,
        quality: AudioQuality,
        state: State
    ) {
        self.id = id
        self.sessionID = sessionID
        self.index = index
        self.start = start
        self.duration = duration
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.quality = quality
        self.state = state
    }

    public var end: Date {
        start.addingTimeInterval(duration)
    }
}

/// Un trou dans l'enregistrement, toujours visible pour l'utilisateur.
public struct RecordingGap: Identifiable, Hashable, Codable, Sendable {
    public enum Cause: String, Codable, Sendable, CaseIterable {
        case phoneCall
        case siri
        case otherAudio
        case systemStop
        case microphoneUnavailable
        case lowBattery
        case appTerminated
        case unknown
    }

    public var id: UUID
    public var sessionID: UUID
    public var start: Date
    public var end: Date
    public var cause: Cause

    public init(id: UUID = UUID(), sessionID: UUID, start: Date, end: Date, cause: Cause) {
        self.id = id
        self.sessionID = sessionID
        self.start = start
        self.end = max(start, end)
        self.cause = cause
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

/// Accès aux tranches audio et aux trous d'une session.
public protocol RecordingRepository: Sendable {
    func segments(sessionID: UUID) async throws -> [AudioSegment]
    func save(_ segment: AudioSegment) async throws
    func gaps(sessionID: UUID) async throws -> [RecordingGap]
    /// Tous les trous, de toutes les sessions, pour la liste du journal.
    func allGaps() async throws -> [RecordingGap]
    func save(_ gap: RecordingGap) async throws
    func deleteAll(sessionID: UUID) async throws
}

/// Efface ce qui a été enregistré pendant une session : audio, niveaux, mouvements, trous.
public protocol SessionDataEraser: Sendable {
    func eraseRecordings(of session: SleepSession) async throws
}

/// Version qui n'efface que les fiches de la base (tranches, trous, événements), pour les tests et les aperçus.
public struct RepositoryDataEraser: SessionDataEraser {
    private let recordings: any RecordingRepository
    private let events: (any NightEventRepository)?

    public init(recordings: any RecordingRepository, events: (any NightEventRepository)? = nil) {
        self.recordings = recordings
        self.events = events
    }

    public func eraseRecordings(of session: SleepSession) async throws {
        try await recordings.deleteAll(sessionID: session.id)
        try await events?.deleteAll(sessionID: session.id)
    }
}

/// Version factice, pour les tests et les aperçus.
public actor InMemoryRecordingRepository: RecordingRepository {
    private var segmentStore: [UUID: AudioSegment] = [:]
    private var gapStore: [UUID: RecordingGap] = [:]

    public init() {}

    public func segments(sessionID: UUID) async throws -> [AudioSegment] {
        segmentStore.values.filter { $0.sessionID == sessionID }.sorted { $0.index < $1.index }
    }

    public func save(_ segment: AudioSegment) async throws {
        segmentStore[segment.id] = segment
    }

    public func gaps(sessionID: UUID) async throws -> [RecordingGap] {
        gapStore.values.filter { $0.sessionID == sessionID }.sorted { $0.start < $1.start }
    }

    public func allGaps() async throws -> [RecordingGap] {
        gapStore.values.sorted { $0.start < $1.start }
    }

    public func save(_ gap: RecordingGap) async throws {
        gapStore[gap.id] = gap
    }

    public func deleteAll(sessionID: UUID) async throws {
        segmentStore = segmentStore.filter { $0.value.sessionID != sessionID }
        gapStore = gapStore.filter { $0.value.sessionID != sessionID }
    }
}
