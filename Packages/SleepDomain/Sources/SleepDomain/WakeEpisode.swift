import Foundation

/// Un réveil pendant la nuit, détecté ou saisi.
public struct WakeEpisode: Identifiable, Hashable, Codable, Sendable {
    /// Durée au-delà de laquelle un réveil compte dans le score (étude, « Score de sommeil »).
    public static let significantDuration: TimeInterval = 5 * 60

    public var id: UUID
    public var start: Date
    public var end: Date
    public var source: DataSource

    public init(id: UUID = UUID(), start: Date, end: Date, source: DataSource = .manual) {
        self.id = id
        self.start = start
        self.end = max(start, end)
        self.source = source
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    /// Vrai pour un réveil de plus de 5 minutes.
    public var isSignificant: Bool {
        duration > WakeEpisode.significantDuration
    }
}
