import Foundation

/// Une nuit ou une sieste. Une correction ne détruit jamais la détection d'origine.
public struct SleepSession: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: SessionKind
    public var state: SessionState
    public var detected: SessionTimes
    public var corrected: SessionTimes
    public var primarySource: DataSource
    public var recordingMode: RecordingMode
    public var analysisVersion: Int?
    public var comment: String?
    public var feeling: WakeFeeling?
    /// Réveils pendant la nuit, détectés ou saisis.
    public var wakeEpisodes: [WakeEpisode]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: SessionKind = .night,
        state: SessionState = .manual,
        detected: SessionTimes = SessionTimes(),
        corrected: SessionTimes = SessionTimes(),
        primarySource: DataSource = .manual,
        recordingMode: RecordingMode = .continuous,
        analysisVersion: Int? = nil,
        comment: String? = nil,
        feeling: WakeFeeling? = nil,
        wakeEpisodes: [WakeEpisode] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.state = state
        self.detected = detected
        self.corrected = corrected
        self.primarySource = primarySource
        self.recordingMode = recordingMode
        self.analysisVersion = analysisVersion
        self.comment = comment
        self.feeling = feeling
        self.wakeEpisodes = wakeEpisodes
        self.createdAt = createdAt
    }

    /// Horaires retenus : la correction l'emporte sur la détection.
    public var times: SessionTimes {
        corrected.overriding(detected)
    }

    /// Date de référence pour trier et regrouper les sessions.
    public var referenceDate: Date {
        times.bedtime ?? times.sleepOnset ?? times.wake ?? createdAt
    }

    /// Temps passé au lit, du coucher au lever.
    public var timeInBed: TimeInterval? {
        interval(from: times.bedtime, to: times.getUp)
    }

    /// Délai d'endormissement, du coucher à l'endormissement.
    public var sleepLatency: TimeInterval? {
        interval(from: times.bedtime, to: times.sleepOnset)
    }

    /// Fenêtre de sommeil, de l'endormissement au réveil. Les éveils sont retirés par l'analyse.
    public var sleepWindow: TimeInterval? {
        interval(from: times.sleepOnset, to: times.wake)
    }

    /// Nombre de réveils de plus de 5 minutes.
    public var significantWakeCount: Int {
        wakeEpisodes.filter(\.isSignificant).count
    }

    /// Temps éveillé pendant la fenêtre de sommeil, d'après les réveils connus.
    public var wakeDuration: TimeInterval {
        guard let onset = times.sleepOnset, let wake = times.wake, wake > onset else { return 0 }
        return wakeEpisodes.reduce(0) { total, episode in
            let start = max(episode.start, onset)
            let end = min(episode.end, wake)
            return total + max(0, end.timeIntervalSince(start))
        }
    }

    /// Durée de sommeil : la fenêtre de sommeil moins les réveils connus.
    public var asleepDuration: TimeInterval? {
        sleepWindow.map { max(0, $0 - wakeDuration) }
    }

    /// Problèmes de cohérence des horaires retenus.
    public var issues: [SessionIssue] {
        var found: [SessionIssue] = []
        let ordered = times.ordered
        if zip(ordered, ordered.dropFirst()).contains(where: { $0 > $1 }) {
            found.append(.timesOutOfOrder)
        }
        if let first = ordered.first, let last = ordered.last, last.timeIntervalSince(first) > 24 * 3600 {
            found.append(.longerThanADay)
        }
        return found
    }

    private func interval(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start, let end, end >= start else { return nil }
        return end.timeIntervalSince(start)
    }
}
