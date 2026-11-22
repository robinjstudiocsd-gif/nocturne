import AVFoundation
import Foundation
import SleepDomain

/// Traitement des blocs du micro pendant la nuit : niveau sonore chaque seconde,
/// et, en mode continu, audio en tranches de 5 minutes.
/// N'est utilisé que depuis le fil de capture ; seul `latestLevelDb` se lit d'ailleurs.
public final class CapturePipeline: @unchecked Sendable {
    /// Ce qu'un bloc a produit : tranches terminées et secondes de niveau.
    public struct Output: Sendable {
        public var finishedSegments: [AudioSegment] = []
        public var levels: [LevelSecond] = []
    }

    public let processingFormat: AVAudioFormat
    public let layout: SegmentLayout

    private let segmentWriter: SegmentWriter?
    private let levelWriter: LevelSeriesWriter
    private var meter: LevelMeter
    private let lock = NSLock()
    private var level: Float?
    private var snapshotSecond = 0
    private var snapshotSegment = 1

    /// - Parameters:
    ///   - mode: seul le mode continu garde l'audio ; les autres gardent le niveau (extraits au lot 3).
    ///   - resume: point de reprise si l'écoute reprend après une coupure de l'app.
    public init(storage: RecordingStorage, layout: SegmentLayout, mode: RecordingMode, quality: AudioQuality, resume: Checkpoint? = nil, segmentDuration: TimeInterval = SegmentLayout.segmentDuration) throws {
        guard mode != .off else { throw RecordingError.microphoneUnavailable }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: quality.sampleRate, channels: 1, interleaved: false) else {
            throw RecordingError.unsupportedFormat
        }
        self.layout = layout
        self.processingFormat = format
        _ = try storage.prepareFolder(for: layout)

        if mode == .continuous {
            segmentWriter = try SegmentWriter(
                root: storage.root,
                layout: layout,
                quality: quality,
                segmentDuration: segmentDuration,
                firstIndex: resume?.nextSegmentIndex ?? 1
            )
        } else {
            segmentWriter = nil
        }

        let levelsURL = storage.url(for: layout.relativeLevelsPath)
        if resume != nil, FileManager.default.fileExists(atPath: levelsURL.path) {
            levelWriter = try LevelSeriesWriter(resuming: levelsURL)
        } else {
            levelWriter = try LevelSeriesWriter(fileURL: levelsURL, start: layout.start)
        }
        meter = LevelMeter(sampleRate: quality.sampleRate, startingSecond: resume?.levelSeconds ?? 0)
        snapshotSecond = resume?.levelSeconds ?? 0
        snapshotSegment = resume?.nextSegmentIndex ?? 1
    }

    /// Dernier niveau mesuré, en dBFS.
    public var latestLevelDb: Float? {
        lock.lock()
        defer { lock.unlock() }
        return level
    }

    /// Rang de la prochaine seconde de niveau, pour le point de reprise.
    public var nextLevelSecond: Int {
        lock.lock()
        defer { lock.unlock() }
        return snapshotSecond
    }

    /// Rang de la prochaine tranche, pour le point de reprise.
    public var nextSegmentIndex: Int {
        lock.lock()
        defer { lock.unlock() }
        return snapshotSegment
    }

    private func updateSnapshot(level newLevel: Float?) {
        lock.lock()
        if let newLevel {
            level = newLevel
        }
        snapshotSecond = meter.currentSecond
        snapshotSegment = segmentWriter?.nextSegmentIndex ?? 1
        lock.unlock()
    }

    /// Traite un bloc au format `processingFormat`, capté à `time`.
    public func process(_ buffer: AVAudioPCMBuffer, at time: Date) throws -> Output {
        var output = Output()
        let second = max(0, Int(time.timeIntervalSince(layout.start)))
        if second > meter.currentSecond + 1 {
            if let pending = meter.flush() {
                output.levels.append(pending)
            }
            meter.skip(to: second)
        }
        if let samples = buffer.floatChannelData?[0] {
            output.levels += meter.add(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
        }
        try levelWriter.append(output.levels)
        if let segmentWriter, let finished = try segmentWriter.append(buffer, at: time) {
            output.finishedSegments.append(finished)
        }
        updateSnapshot(level: output.levels.last?.meanDb)
        return output
    }

    /// Coupure : la tranche en cours est fermée, marquée tronquée.
    public func interrupt() -> AudioSegment? {
        if let pending = meter.flush() {
            try? levelWriter.append([pending])
        }
        let segment = segmentWriter?.finish(state: .truncated)
        updateSnapshot(level: nil)
        return segment
    }

    /// Fin de la nuit : tout est fermé proprement.
    public func finish() -> AudioSegment? {
        if let pending = meter.flush() {
            try? levelWriter.append([pending])
        }
        let last = segmentWriter?.finish(state: .complete)
        try? levelWriter.close()
        updateSnapshot(level: nil)
        return last
    }
}
