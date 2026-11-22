import Foundation

/// Rangement des fichiers d'une nuit : Application Support/Recordings/aaaa-mm-jj/<session>/.
public struct SegmentLayout: Sendable {
    /// Durée d'une tranche d'audio continu.
    public static let segmentDuration: TimeInterval = 300

    public let sessionID: UUID
    public let start: Date
    private let calendar: Calendar

    public init(sessionID: UUID, start: Date, calendar: Calendar = .current) {
        self.sessionID = sessionID
        self.start = start
        self.calendar = calendar
    }

    /// Dossier de la nuit, relatif à Application Support.
    public var relativeFolder: String {
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "Recordings/\(day)/\(sessionID.uuidString)"
    }

    public func relativeSegmentPath(index: Int) -> String {
        relativeFolder + String(format: "/tranche-%03d.m4a", index)
    }

    public var relativeLevelsPath: String {
        relativeFolder + "/niveaux.ncls"
    }

    /// Vrai quand la tranche en cours a atteint sa durée.
    public static func needsRotation(segmentStart: Date, now: Date, duration: TimeInterval = segmentDuration) -> Bool {
        now.timeIntervalSince(segmentStart) >= duration
    }
}
