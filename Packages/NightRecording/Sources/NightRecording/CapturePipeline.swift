import AVFoundation
import Foundation
import SleepDomain

/// Traitement des blocs du micro pendant la nuit : niveau sonore chaque seconde, bruit de fond,
/// classement des sons au-dessus du bruit de fond, et, en mode continu, audio en tranches de 5 minutes.
/// N'est utilisé que depuis le fil de capture ; seuls les instantanés sous verrou se lisent d'ailleurs.
public final class CapturePipeline: @unchecked Sendable {
    /// Ce qu'un bloc a produit : tranches terminées, secondes de niveau et événements refermés.
    public struct Output: Sendable {
        public var finishedSegments: [AudioSegment] = []
        public var levels: [LevelSecond] = []
        public var events: [NightEvent] = []
    }

    /// Fabrique le classifieur de sons d'une nuit, au format de la capture.
    public typealias ClassifierFactory = @Sendable (AVAudioFormat, Date) -> (any SoundClassifying)?

    public let processingFormat: AVAudioFormat
    public let layout: SegmentLayout

    private let segmentWriter: SegmentWriter?
    private let levelWriter: LevelSeriesWriter
    private var meter: LevelMeter
    private let lock = NSLock()
    private var level: Float?
    private var snapshotSecond = 0
    private var snapshotSegment = 1

    private let classifier: (any SoundClassifying)?
    private var noiseFloor = NoiseFloorTracker()
    private var trigger: DetectionTrigger
    private var aggregator: EventAggregator
    private var analyzeUntilSecond = -1
    /// Écart au bruit de fond des dernières secondes, pour l'intensité des événements.
    private var recentIntensity: [Int: Float] = [:]

    /// - Parameters:
    ///   - mode: seul le mode continu garde l'audio ; les autres gardent le niveau (extraits au lot 3).
    ///   - resume: point de reprise si l'écoute reprend après une coupure de l'app.
    public init(
        storage: RecordingStorage,
        layout: SegmentLayout,
        mode: RecordingMode,
        quality: AudioQuality,
        resume: Checkpoint? = nil,
        segmentDuration: TimeInterval = SegmentLayout.segmentDuration,
        threshold: Float = DetectionTrigger.defaultThreshold,
        classifier makeClassifier: ClassifierFactory? = nil
    ) throws {
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
        trigger = DetectionTrigger(threshold: threshold)
        aggregator = EventAggregator(sessionID: layout.sessionID)
        classifier = makeClassifier?(format, layout.start)
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
        output.events = classify(buffer, second: second, time: time, levels: output.levels)
        updateSnapshot(level: output.levels.last?.meanDb)
        return output
    }

    /// Bruit de fond, déclenchement du classifieur, puis regroupement des détections en événements.
    private func classify(_ buffer: AVAudioPCMBuffer, second: Int, time: Date, levels: [LevelSecond]) -> [NightEvent] {
        guard let classifier else { return [] }
        for level in levels {
            let floor = noiseFloor.add(level.meanDb)
            recentIntensity[level.second] = level.maxDb - floor
            if trigger.shouldAnalyze(second: level.second, level: level.maxDb, floor: floor) {
                analyzeUntilSecond = level.second + 1
            }
        }
        recentIntensity = recentIntensity.filter { $0.key >= second - 120 }
        let position = AVAudioFramePosition(time.timeIntervalSince(layout.start) * processingFormat.sampleRate)
        classifier.process(buffer, framePosition: position, active: second <= analyzeUntilSecond)
        var events = absorb(classifier.drain())
        // Les dernières détections arrivent avec un peu de retard : on ne referme qu'après 5 s.
        events += aggregator.close(before: time.addingTimeInterval(-5))
        return events.sorted { $0.start < $1.start }
    }

    private func absorb(_ detections: [SoundDetection]) -> [NightEvent] {
        var events: [NightEvent] = []
        for var detection in detections {
            let second = Int(detection.time.timeIntervalSince(layout.start))
            let intensity = recentIntensity[second] ?? recentIntensity[second - 1] ?? recentIntensity[second + 1] ?? 0
            detection.intensity = Double(max(0, intensity))
            events += aggregator.add(detection)
        }
        return events
    }

    /// Fin de la nuit côté événements : le classifieur livre ses derniers résultats, tout est refermé.
    public func closeEvents() -> [NightEvent] {
        guard let classifier else { return [] }
        classifier.finish()
        let events = absorb(classifier.drain()) + aggregator.flush()
        return events.sorted { $0.start < $1.start }
    }

    /// Coupure : la tranche en cours est fermée, marquée tronquée.
    public func interrupt() -> AudioSegment? {
        classifier?.reset()
        analyzeUntilSecond = -1
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
