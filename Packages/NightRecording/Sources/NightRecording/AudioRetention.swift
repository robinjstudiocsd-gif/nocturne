import AVFoundation
import CoreMedia
import Foundation
import SleepDomain

/// L'audio d'une nuit posé sur sa ligne du temps : chaque tranche ou extrait à son heure, du silence entre deux.
@MainActor
enum NightComposition {
    struct Built {
        let composition: AVMutableComposition
        /// Fin du dernier son, en secondes depuis le début de la nuit.
        let duration: TimeInterval
    }

    /// Construit la composition ; renvoie nil s'il n'y a aucun son lisible.
    static func build(segments: [AudioSegment], start: Date, storage: RecordingStorage) async -> Built? {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        var cursor = CMTime.zero
        var hasAudio = false
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let url = storage.url(for: segment.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let asset = AVURLAsset(url: url)
            guard
                let source = try? await asset.loadTracks(withMediaType: .audio).first,
                let length = try? await asset.load(.duration),
                length.seconds > 0
            else { continue }
            var at = CMTime(seconds: max(0, segment.start.timeIntervalSince(start)), preferredTimescale: 600)
            if at > cursor {
                track.insertEmptyTimeRange(CMTimeRange(start: cursor, end: at))
            } else {
                at = cursor
            }
            do {
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: at)
                cursor = at + length
                hasAudio = true
            } catch {
                continue
            }
        }
        return hasAudio ? Built(composition: composition, duration: cursor.seconds) : nil
    }

    /// Exporte un passage de la composition en fichier AAC.
    static func export(_ composition: AVMutableComposition, from: TimeInterval, to: TimeInterval, url: URL) async throws {
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecordingError.unsupportedFormat
        }
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: max(0, from), preferredTimescale: 600),
            end: CMTime(seconds: max(from, to), preferredTimescale: 600)
        )
        try? FileManager.default.removeItem(at: url)
        try await session.export(to: url, as: .m4a)
    }
}

/// Conservation de l'audio (étude, « Enregistrement audio ») : l'audio continu des dernières nuits est gardé en entier ;
/// pour les nuits plus anciennes, il est réduit aux passages autour des événements, d'environ 30 secondes chacun.
@MainActor
public final class AudioRetention {
    /// Son gardé avant chaque événement et après sa partie gardée.
    public static let margin: TimeInterval = 5
    /// Partie gardée d'un long événement.
    public static let eventPart: TimeInterval = 20

    private let storage: RecordingStorage
    private let sessions: any SleepSessionRepository
    private let recordings: any RecordingRepository
    private let events: any NightEventRepository
    private let journal: any DiagnosticJournal

    public init(
        storage: RecordingStorage,
        sessions: any SleepSessionRepository,
        recordings: any RecordingRepository,
        events: any NightEventRepository,
        journal: any DiagnosticJournal
    ) {
        self.storage = storage
        self.sessions = sessions
        self.recordings = recordings
        self.events = events
        self.journal = journal
    }

    /// Passages à garder : autour de chaque événement, fusionnés quand ils se touchent. En secondes depuis `start`.
    public static func passages(for events: [NightEvent], start: Date) -> [ClosedRange<TimeInterval>] {
        let windows = events
            .map { event -> ClosedRange<TimeInterval> in
                let from = max(0, event.start.timeIntervalSince(start) - margin)
                let kept = min(event.duration, eventPart)
                return from...(event.start.timeIntervalSince(start) + kept + margin)
            }
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<TimeInterval>] = []
        for window in windows {
            if let last = merged.last, window.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
            } else {
                merged.append(window)
            }
        }
        return merged
    }

    /// Réduit l'audio continu des nuits au-delà des `keepNights` plus récentes. Renvoie le nombre de nuits réduites.
    @discardableResult
    public func apply(keepingNights keepNights: Int) async -> Int {
        guard let all = try? await sessions.sessions(in: nil) else { return 0 }
        var withAudio = 0
        var reduced = 0
        for session in all where session.state != .running {
            guard let segments = try? await recordings.segments(sessionID: session.id) else { continue }
            let tranches = segments.filter { $0.relativePath.contains("/tranche-") }
            guard !tranches.isEmpty else { continue }
            withAudio += 1
            guard withAudio > max(1, keepNights) else { continue }
            if await reduce(session, tranches: tranches, existing: segments) {
                reduced += 1
            }
        }
        return reduced
    }

    private func reduce(_ session: SleepSession, tranches: [AudioSegment], existing: [AudioSegment]) async -> Bool {
        let start = session.detected.bedtime ?? tranches.first?.start ?? session.createdAt
        guard
            let nightEvents = try? await events.events(sessionID: session.id),
            let built = await NightComposition.build(segments: tranches, start: start, storage: storage)
        else { return false }
        let layout = SegmentLayout(sessionID: session.id, start: start)
        let composition = built.composition
        let duration = built.duration
        var index = (existing.map(\.index).max() ?? 0) + 1
        var linked: [NightEvent] = []
        var clips: [AudioSegment] = []
        let folder = storage.folder(sessionID: session.id) ?? storage.root.appendingPathComponent(layout.relativeFolder, isDirectory: true)
        for passage in Self.passages(for: nightEvents, start: start) {
            let upper = min(passage.upperBound, duration)
            guard upper > passage.lowerBound else { continue }
            let name = String(format: "extrait-%03d.m4a", index)
            let url = folder.appendingPathComponent(name)
            do {
                try await NightComposition.export(composition, from: passage.lowerBound, to: upper, url: url)
            } catch {
                journal.record("Réduction de l’audio impossible : \(error.localizedDescription)")
                return false
            }
            let relativePath = "Recordings/\(folder.deletingLastPathComponent().lastPathComponent)/\(session.id.uuidString)/\(name)"
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let clipStart = start.addingTimeInterval(passage.lowerBound)
            clips.append(AudioSegment(
                sessionID: session.id,
                index: index,
                start: clipStart,
                duration: upper - passage.lowerBound,
                relativePath: relativePath,
                byteSize: Int64(size),
                quality: tranches.first?.quality ?? .standard,
                state: .complete
            ))
            for var event in nightEvents where passage.contains(event.start.timeIntervalSince(start)) {
                event.clipPath = relativePath
                linked.append(event)
            }
            index += 1
        }
        // Les extraits d'abord, puis seulement l'effacement des tranches.
        for clip in clips {
            try? await recordings.save(clip)
        }
        try? await events.save(linked)
        for tranche in tranches {
            try? FileManager.default.removeItem(at: storage.url(for: tranche.relativePath))
            try? await recordings.delete(segmentID: tranche.id)
        }
        let before = tranches.reduce(0) { $0 + $1.byteSize }
        let after = clips.reduce(0) { $0 + $1.byteSize }
        journal.record("Audio réduit pour une nuit : \(clips.count) passages gardés, \(SleepFormat().bytes(before)) → \(SleepFormat().bytes(after))")
        return true
    }
}
