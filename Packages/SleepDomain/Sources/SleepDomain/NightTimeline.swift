import Foundation

/// La nuit prête à réécouter : niveau sonore en colonnes, événements, trous et passages calmes.
/// Les positions sont en secondes depuis le début de l'écoute.
public struct NightTimeline: Equatable, Sendable {
    public var start: Date
    public var duration: TimeInterval
    /// Niveau le plus fort de chaque colonne, en dB relatifs ; nil sans mesure.
    public var columns: [Float?]
    public var events: [NightEvent]
    public var gaps: [RecordingGap]
    /// Passages calmes sautés par « Sauter les silences ».
    public var quietRanges: [ClosedRange<TimeInterval>]
    /// Vrai si l'audio continu de la nuit est disponible.
    public var hasAudio: Bool

    public init(
        start: Date,
        duration: TimeInterval,
        columns: [Float?] = [],
        events: [NightEvent] = [],
        gaps: [RecordingGap] = [],
        quietRanges: [ClosedRange<TimeInterval>] = [],
        hasAudio: Bool = false
    ) {
        self.start = start
        self.duration = max(0, duration)
        self.columns = columns
        self.events = events.sorted { $0.start < $1.start }
        self.gaps = gaps
        self.quietRanges = quietRanges
        self.hasAudio = hasAudio
    }

    public func offset(of date: Date) -> TimeInterval {
        min(duration, max(0, date.timeIntervalSince(start)))
    }

    public func date(at position: TimeInterval) -> Date {
        start.addingTimeInterval(position)
    }

    /// L'événement qui contient la position, ou nil.
    public func event(at position: TimeInterval) -> NightEvent? {
        events.last { offset(of: $0.start) <= position && position <= offset(of: $0.end) }
    }

    /// Le prochain événement qui commence après la position (une seconde de marge pour quitter l'événement en cours).
    public func nextEvent(after position: TimeInterval, kinds: Set<EventKind>? = nil) -> NightEvent? {
        events.first { offset(of: $0.start) > position + 1 && (kinds?.contains($0.kind) ?? true) }
    }

    /// L'événement précédent : celui en cours si on est entré depuis plus de 3 s, sinon celui d'avant.
    public func previousEvent(before position: TimeInterval, kinds: Set<EventKind>? = nil) -> NightEvent? {
        events.last { offset(of: $0.start) < position - 3 && (kinds?.contains($0.kind) ?? true) }
    }

    /// Position après le saut d'un passage calme, ou la même position.
    public func skippingQuiet(_ position: TimeInterval) -> TimeInterval {
        guard let range = quietRanges.first(where: { $0.contains(position) }) else { return position }
        return min(duration, range.upperBound)
    }
}

/// Construction de la frise à partir des niveaux de chaque seconde.
public enum TimelineBuilder {
    /// Réduit les niveaux à `count` colonnes, en gardant le plus fort de chaque colonne.
    public static func columns(_ levels: [Float?], count: Int) -> [Float?] {
        guard count > 0, !levels.isEmpty else { return [] }
        return (0..<count).map { column in
            let from = column * levels.count / count
            let to = max(from + 1, (column + 1) * levels.count / count)
            return levels[from..<min(to, levels.count)].compactMap { $0 }.max()
        }
    }

    /// Bruit de fond de la nuit : le niveau atteint 20 % du temps.
    public static func floor(_ means: [Float?]) -> Float? {
        let measured = means.compactMap { $0 }.sorted()
        guard !measured.isEmpty else { return nil }
        return measured[min(measured.count - 1, measured.count / 5)]
    }

    /// Passages calmes d'au moins `minimum` secondes : sous le bruit de fond plus le seuil, hors événements.
    /// On garde 2 secondes de son de chaque côté.
    public static func quietRanges(
        peaks: [Float?],
        floor: Float,
        threshold: Float = 10,
        busy: [ClosedRange<TimeInterval>] = [],
        minimum: Int = 10
    ) -> [ClosedRange<TimeInterval>] {
        var ranges: [ClosedRange<TimeInterval>] = []
        var runStart: Int?
        func isQuiet(_ second: Int) -> Bool {
            let level = peaks[second] ?? floor
            let time = TimeInterval(second)
            return level < floor + threshold && !busy.contains { $0.contains(time) }
        }
        for second in 0...peaks.count {
            let quiet = second < peaks.count && isQuiet(second)
            if quiet, runStart == nil {
                runStart = second
            } else if !quiet, let start = runStart {
                if second - start >= minimum {
                    ranges.append(TimeInterval(start + 2)...TimeInterval(second - 2))
                }
                runStart = nil
            }
        }
        return ranges
    }
}

/// État de la réécoute.
public struct ReplayState: Equatable, Sendable {
    public var position: TimeInterval
    public var duration: TimeInterval
    public var isPlaying: Bool
    public var rate: Float
    public var skipsSilences: Bool

    public init(position: TimeInterval = 0, duration: TimeInterval = 0, isPlaying: Bool = false, rate: Float = 1, skipsSilences: Bool = true) {
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.rate = rate
        self.skipsSilences = skipsSilences
    }

    /// Vitesses proposées, dans l'ordre du bouton.
    public static let rates: [Float] = [1, 1.5, 2, 0.5]
}

/// Lecteur de la nuit entière, fourni par l'app.
@MainActor
public protocol NightReplaying: AnyObject {
    /// Prépare la lecture des tranches de la nuit, bout à bout, trous compris.
    func load(_ session: SleepSession) async throws -> NightTimeline
    func updates() -> AsyncStream<ReplayState>
    func play()
    func pause()
    func seek(to position: TimeInterval)
    func setRate(_ rate: Float)
    func setSkipsSilences(_ skips: Bool)
    func stop()
    /// Exporte une minute autour de la position, pour la feuille de partage d'iOS.
    func exportPassage(around position: TimeInterval) async throws -> URL
}
