import Foundation
import SleepAnalysis
import SleepDomain

/// Profil d'une nuit d'après ses fichiers : niveau sonore chaque seconde, mouvements par 30 secondes,
/// déverrouillages de l'iPhone et sons reconnus pendant la nuit.
public struct NightAnalyzer: Sendable {
    private let storage: RecordingStorage

    public init(storage: RecordingStorage) {
        self.storage = storage
    }

    /// Mesures de la nuit, alignées sur l'heure du coucher détectée ; nil si la nuit n'a pas d'horaires.
    public func input(for session: SleepSession, events: [NightEvent]) -> ProfileInput? {
        guard
            let start = session.detected.bedtime,
            let end = session.detected.getUp ?? session.detected.wake,
            end > start
        else { return nil }
        var input = ProfileInput(kind: session.kind, start: start, end: end, events: events)
        guard let folder = storage.folder(sessionID: session.id) else { return input }
        if let data = try? Data(contentsOf: folder.appendingPathComponent(SegmentLayout.levelsFileName)),
           let levels = try? LevelSeries.read(data) {
            let offset = Int(levels.start.timeIntervalSince(start).rounded())
            input.peaks = Self.align(levels.peaks, offset: offset)
            input.means = Self.align(levels.means, offset: offset)
        }
        if let data = try? Data(contentsOf: folder.appendingPathComponent(SegmentLayout.motionFileName)),
           let motion = MotionSeries.read(data) {
            let motionStart = MotionSeries.start(of: data) ?? start
            let offset = Int((motionStart.timeIntervalSince(start) / NightProfile.epoch).rounded())
            input.motion = Self.align(motion, offset: offset)
        }
        if var unlocks = UnlockLog.read(from: folder) {
            unlocks.finish(at: end)
            input.unlocks = unlocks.usablePeriods
        }
        return input
    }

    /// Profil de la nuit, ou nil si la nuit n'a pas d'horaires.
    public func profile(for session: SleepSession, events: [NightEvent]) -> NightProfile? {
        input(for: session, events: events).map(NightProfiler.analyze)
    }

    /// Décale une série pour qu'elle commence à l'heure du coucher.
    static func align(_ values: [Float?], offset: Int) -> [Float?] {
        if offset > 0 {
            return [Float?](repeating: nil, count: offset) + values
        }
        if offset < 0 {
            return Array(values.dropFirst(-offset))
        }
        return values
    }

    /// Résumé pour le journal de diagnostic.
    public static func journalLine(_ profile: NightProfile, format: SleepFormat = SleepFormat()) -> String {
        var parts: [String] = []
        if let onset = profile.sleepOnset {
            parts.append("endormissement \(format.clock(onset))")
        } else {
            parts.append("endormissement introuvable")
        }
        if let wake = profile.wake {
            parts.append("réveil \(format.clock(wake))")
        }
        parts.append("\(profile.wakeEpisodes.count) réveil(s) dans la nuit")
        let sources = [profile.usedMotion ? "mouvements" : nil, profile.usedSound ? "son" : nil].compactMap { $0 }
        parts.append(sources.isEmpty ? "aucune mesure" : sources.joined(separator: " et "))
        parts.append("fiabilité \(profile.reliability.title)")
        return parts.joined(separator: " · ")
    }
}
