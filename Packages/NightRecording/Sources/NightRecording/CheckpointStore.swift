import Foundation
import SleepDomain

/// Point de reprise écrit chaque minute pendant la nuit.
public struct Checkpoint: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var lastBeat: Date
    public var nextSegmentIndex: Int
    public var levelSeconds: Int
    /// Réveil prévu, retrouvé si l'app est relancée pendant la nuit.
    public var alarm: NightAlarm?

    public init(sessionID: UUID, lastBeat: Date, nextSegmentIndex: Int, levelSeconds: Int, alarm: NightAlarm? = nil) {
        self.sessionID = sessionID
        self.lastBeat = lastBeat
        self.nextSegmentIndex = nextSegmentIndex
        self.levelSeconds = levelSeconds
        self.alarm = alarm
    }
}

/// Enregistre le point de reprise dans un petit fichier, de façon atomique.
public struct CheckpointStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func write(_ checkpoint: Checkpoint) throws {
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: fileURL, options: .atomic)
    }

    public func read() -> Checkpoint? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Checkpoint.self, from: data)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Que faire au lancement quand une nuit était en cours ?
public enum RecoveryAction: Equatable, Sendable {
    /// Rien à reprendre.
    case nothing
    /// L'app a été arrêtée pendant la nuit : on note le trou, puis on reprend l'écoute.
    case resume(gap: RecordingGap)
    /// La nuit est trop ancienne pour être reprise : on la termine au dernier battement.
    case close(at: Date, gap: RecordingGap)
}

/// Décide de la reprise d'une nuit interrompue (app fermée, arrêt du système, batterie vide).
public enum RecoveryPlanner {
    /// Au-delà de cette durée sans battement, la nuit n'est plus reprise automatiquement.
    public static let maximumResumeDelay: TimeInterval = 3 * 3_600

    public static func plan(checkpoint: Checkpoint?, running: SleepSession?, now: Date) -> RecoveryAction {
        guard let running, running.state == .running else { return .nothing }
        // Sans écoute, iOS met l'app en pause la nuit : il n'y a rien à reprendre.
        guard running.recordingMode != .off else { return .nothing }
        let lastBeat = checkpoint.map { $0.sessionID == running.id ? $0.lastBeat : running.referenceDate } ?? running.referenceDate
        let gap = RecordingGap(sessionID: running.id, start: lastBeat, end: now, cause: .appTerminated)
        if now.timeIntervalSince(lastBeat) > maximumResumeDelay {
            return .close(at: lastBeat, gap: gap)
        }
        return .resume(gap: gap)
    }
}
