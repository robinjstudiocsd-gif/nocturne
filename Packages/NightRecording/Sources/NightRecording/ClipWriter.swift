import AVFoundation
import Foundation
import SleepDomain

/// Extraits des modes « événements » et « économie » : chaque passage au-dessus du bruit de fond,
/// avec 5 secondes avant et après. Un extrait est une tranche posée à son heure :
/// la réécoute les enchaîne comme l'audio continu, avec du silence entre deux.
/// À utiliser depuis une seule file : la file de capture du micro.
public final class ClipWriter {
    /// Son gardé avant et après chaque passage.
    public static let margin: TimeInterval = 5

    private let root: URL
    private let layout: SegmentLayout
    private let quality: AudioQuality
    private let maxDuration: TimeInterval
    private let maxClips: Int?
    private var reserve: [(BufferBox, Date)] = []
    private var reserveDuration: TimeInterval = 0
    private var file: AVAudioFile?
    private var current: AudioSegment?
    private var frames: AVAudioFramePosition = 0
    private var activeUntil = Date.distantPast
    private var nextIndex: Int
    private var written = 0

    /// - Parameters:
    ///   - maxDuration: longueur maximale d'un extrait ; un long passage se poursuit dans l'extrait suivant.
    ///   - maxClips: nombre maximal d'extraits pour la nuit (mode économie), ou nil.
    public init(root: URL, layout: SegmentLayout, quality: AudioQuality, maxDuration: TimeInterval, maxClips: Int?, firstIndex: Int = 1) throws {
        self.root = root
        self.layout = layout
        self.quality = quality
        self.maxDuration = maxDuration
        self.maxClips = maxClips
        self.nextIndex = firstIndex
        try FileManager.default.createDirectory(at: root.appendingPathComponent(layout.relativeFolder, isDirectory: true), withIntermediateDirectories: true)
    }

    /// Réglages des extraits selon le mode d'écoute (étude : 30 extraits de 15 s au plus en économie).
    public static func limits(for mode: RecordingMode) -> (maxDuration: TimeInterval, maxClips: Int?)? {
        switch mode {
        case .events: return (120, nil)
        case .economy: return (15, 30)
        case .continuous, .off: return nil
        }
    }

    public var nextClipIndex: Int {
        nextIndex
    }

    /// Ajoute un bloc ; `loud` indique que le son dépasse le bruit de fond.
    /// Renvoie l'extrait qui vient de se terminer, s'il y en a un.
    public func append(_ buffer: AVAudioPCMBuffer, at time: Date, loud: Bool) throws -> AudioSegment? {
        if loud {
            activeUntil = time.addingTimeInterval(Self.margin)
        }
        if file != nil {
            try write(buffer)
            if time >= activeUntil || Double(frames) / quality.sampleRate >= maxDuration {
                return close(state: .complete)
            }
            return nil
        }
        if loud, maxClips.map({ written < $0 }) ?? true {
            try open(start: reserve.first?.1 ?? time)
            for (kept, _) in reserve {
                try write(kept.buffer)
            }
            reserve.removeAll()
            reserveDuration = 0
            try write(buffer)
            return nil
        }
        keep(buffer, at: time)
        return nil
    }

    /// Coupure ou fin de la nuit : l'extrait en cours est refermé.
    public func finish(state: AudioSegment.State = .complete) -> AudioSegment? {
        reserve.removeAll()
        reserveDuration = 0
        return close(state: state)
    }

    private func keep(_ buffer: AVAudioPCMBuffer, at time: Date) {
        guard let box = BufferBox(copying: buffer) else { return }
        reserve.append((box, time))
        reserveDuration += Double(buffer.frameLength) / buffer.format.sampleRate
        while reserveDuration > Self.margin, let first = reserve.first {
            reserveDuration -= Double(first.0.buffer.frameLength) / first.0.buffer.format.sampleRate
            reserve.removeFirst()
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) throws {
        try file?.write(from: buffer)
        frames += AVAudioFramePosition(buffer.frameLength)
    }

    private func open(start: Date) throws {
        let index = nextIndex
        nextIndex += 1
        let relativePath = layout.relativeClipPath(index: index)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: quality.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: quality.bitRate
        ]
        file = try AVAudioFile(forWriting: root.appendingPathComponent(relativePath), settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        frames = 0
        current = AudioSegment(sessionID: layout.sessionID, index: index, start: start, duration: 0, relativePath: relativePath, byteSize: 0, quality: quality, state: .recording)
    }

    private func close(state: AudioSegment.State) -> AudioSegment? {
        guard var clip = current else { return nil }
        file = nil
        current = nil
        written += 1
        let size = (try? root.appendingPathComponent(clip.relativePath).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        clip.duration = Double(frames) / quality.sampleRate
        clip.byteSize = Int64(size)
        clip.state = state
        return clip
    }
}
