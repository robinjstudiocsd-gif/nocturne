import AVFoundation
import Foundation
import SleepDomain

/// Écrit l'audio continu de la nuit en tranches AAC mono, une nouvelle tranche toutes les 5 minutes.
/// À utiliser depuis une seule file : la file de capture du micro.
public final class SegmentWriter {
    public let layout: SegmentLayout
    public let quality: AudioQuality
    public let processingFormat: AVAudioFormat

    private let root: URL
    private let segmentDuration: TimeInterval
    private var file: AVAudioFile?
    private var current: AudioSegment?
    private var framesInSegment: AVAudioFramePosition = 0
    private var nextIndex = 1

    /// - Parameters:
    ///   - root: dossier Application Support de l'app.
    ///   - segmentDuration: 300 s ; plus court seulement dans les tests.
    public init(root: URL, layout: SegmentLayout, quality: AudioQuality, segmentDuration: TimeInterval = SegmentLayout.segmentDuration, firstIndex: Int = 1) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: quality.sampleRate, channels: 1, interleaved: false) else {
            throw RecordingError.unsupportedFormat
        }
        self.root = root
        self.layout = layout
        self.quality = quality
        self.processingFormat = format
        self.segmentDuration = segmentDuration
        self.nextIndex = firstIndex
        try FileManager.default.createDirectory(at: root.appendingPathComponent(layout.relativeFolder, isDirectory: true), withIntermediateDirectories: true)
    }

    /// Rang de la prochaine tranche, pour le point de reprise.
    public var nextSegmentIndex: Int {
        nextIndex
    }

    /// Ajoute un bloc d'audio au format `processingFormat`.
    /// Renvoie la tranche qui vient de se terminer, s'il y en a une.
    @discardableResult
    public func append(_ buffer: AVAudioPCMBuffer, at time: Date) throws -> AudioSegment? {
        var finished: AudioSegment?
        if let current, SegmentLayout.needsRotation(segmentStart: current.start, now: time, duration: segmentDuration) {
            finished = closeCurrent(state: .complete)
        }
        if file == nil {
            try openSegment(start: time)
        }
        try file?.write(from: buffer)
        framesInSegment += AVAudioFramePosition(buffer.frameLength)
        return finished
    }

    /// Termine la tranche en cours, par exemple à l'arrêt de la nuit ou lors d'une coupure.
    @discardableResult
    public func finish(state: AudioSegment.State = .complete) -> AudioSegment? {
        closeCurrent(state: state)
    }

    private func openSegment(start: Date) throws {
        let index = nextIndex
        nextIndex += 1
        let relativePath = layout.relativeSegmentPath(index: index)
        let url = root.appendingPathComponent(relativePath)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: quality.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: quality.bitRate
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        framesInSegment = 0
        current = AudioSegment(
            sessionID: layout.sessionID,
            index: index,
            start: start,
            duration: 0,
            relativePath: relativePath,
            byteSize: 0,
            quality: quality,
            state: .recording
        )
    }

    private func closeCurrent(state: AudioSegment.State) -> AudioSegment? {
        guard var segment = current else { return nil }
        file = nil
        current = nil
        let url = root.appendingPathComponent(segment.relativePath)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        segment.duration = Double(framesInSegment) / quality.sampleRate
        segment.byteSize = Int64(size)
        segment.state = state
        return segment
    }
}

/// Erreurs de l'enregistrement.
public enum RecordingError: Error, Equatable, Sendable {
    case unsupportedFormat
    case microphoneUnavailable
    case permissionDenied
}
