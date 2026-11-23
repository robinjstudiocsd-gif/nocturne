import AVFoundation
import CoreMedia
import Foundation
import SleepDomain

/// Ce que la chaîne de capture attend d'un classifieur de sons.
/// Toutes les méthodes sont appelées depuis le fil de capture.
public protocol SoundClassifying: AnyObject, Sendable {
    /// Confie un bloc : analysé si `active`, sinon gardé quelques secondes en réserve.
    func process(_ buffer: AVAudioPCMBuffer, framePosition: AVAudioFramePosition, active: Bool)
    /// Les détections arrivées depuis le dernier appel.
    func drain() -> [SoundDetection]
    /// Coupure : l'analyse en cours s'arrête, la réserve est vidée.
    func reset()
    /// Fin de la nuit : les dernières détections sont livrées avant le retour.
    func finish()
}

/// Copie d'un bloc audio, pour le confier à une autre file.
struct BufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init?(copying source: AVAudioPCMBuffer) {
        guard
            let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: max(1, source.frameLength)),
            let from = source.floatChannelData,
            let to = copy.floatChannelData
        else { return nil }
        copy.frameLength = source.frameLength
        for channel in 0..<Int(source.format.channelCount) {
            to[channel].update(from: from[channel], count: Int(source.frameLength))
        }
        buffer = copy
    }
}

#if canImport(SoundAnalysis)
import SoundAnalysis

/// Fait écouter au classifieur de sons d'Apple (plus de 300 sons, sur l'iPhone) les passages retenus par le déclencheur.
/// L'analyse tourne sur une file à part ; une réserve de 2 secondes garde le début de chaque son.
public final class SoundClassifier: SoundClassifying, @unchecked Sendable {
    private let queue = DispatchQueue(label: "nocturne.classification", qos: .utility)
    private let format: AVAudioFormat
    private let start: Date
    private let preRollFrames: AVAudioFrameCount
    private let request: SNClassifySoundRequest
    private let lock = NSLock()
    private var inbox: [SoundDetection] = []

    // Utilisés seulement sur `queue`.
    private var reserve: [(BufferBox, AVAudioFramePosition)] = []
    private var reserveFrames: AVAudioFrameCount = 0
    private var analyzer: SNAudioStreamAnalyzer?
    private var observer: ResultsObserver?

    /// Renvoie nil si le classifieur intégré n'est pas disponible.
    public init?(format: AVAudioFormat, start: Date, preRollSeconds: Double = 2) {
        guard let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return nil }
        request.overlapFactor = 0
        self.request = request
        self.format = format
        self.start = start
        self.preRollFrames = AVAudioFrameCount(format.sampleRate * preRollSeconds)
    }

    public func process(_ buffer: AVAudioPCMBuffer, framePosition: AVAudioFramePosition, active: Bool) {
        guard let box = BufferBox(copying: buffer) else { return }
        queue.async { [self] in
            if active {
                feed(box, at: framePosition)
            } else {
                stopAnalysis()
                keep(box, at: framePosition)
            }
        }
    }

    public func drain() -> [SoundDetection] {
        lock.lock()
        defer { lock.unlock() }
        let taken = inbox
        inbox.removeAll()
        return taken.sorted { $0.time < $1.time }
    }

    public func reset() {
        queue.async { [self] in
            stopAnalysis()
            reserve.removeAll()
            reserveFrames = 0
        }
    }

    public func finish() {
        queue.sync {
            stopAnalysis()
            reserve.removeAll()
            reserveFrames = 0
        }
    }

    // MARK: - Sur la file d'analyse

    private func feed(_ box: BufferBox, at position: AVAudioFramePosition) {
        if analyzer == nil {
            startAnalysis()
            for (kept, keptPosition) in reserve {
                analyzer?.analyze(kept.buffer, atAudioFramePosition: keptPosition)
            }
            reserve.removeAll()
            reserveFrames = 0
        }
        analyzer?.analyze(box.buffer, atAudioFramePosition: position)
    }

    private func keep(_ box: BufferBox, at position: AVAudioFramePosition) {
        reserve.append((box, position))
        reserveFrames += box.buffer.frameLength
        while reserveFrames > preRollFrames, let first = reserve.first {
            reserveFrames -= first.0.buffer.frameLength
            reserve.removeFirst()
        }
    }

    private func startAnalysis() {
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let observer = ResultsObserver(start: start) { [weak self] detection in
            self?.deliver(detection)
        }
        do {
            try analyzer.add(request, withObserver: observer)
            self.analyzer = analyzer
            self.observer = observer
        } catch {
            self.analyzer = nil
            self.observer = nil
        }
    }

    private func stopAnalysis() {
        guard let analyzer else { return }
        analyzer.completeAnalysis()
        self.analyzer = nil
        observer = nil
    }

    private func deliver(_ detection: SoundDetection) {
        lock.lock()
        inbox.append(detection)
        lock.unlock()
    }
}

/// Reçoit les résultats du classifieur et garde l'étiquette la plus probable de chaque fenêtre.
private final class ResultsObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    private let start: Date
    private let deliver: @Sendable (SoundDetection) -> Void

    init(start: Date, deliver: @escaping @Sendable (SoundDetection) -> Void) {
        self.start = start
        self.deliver = deliver
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard
            let result = result as? SNClassificationResult,
            let best = result.classifications.max(by: { $0.confidence < $1.confidence }),
            best.confidence >= SoundLabelMap.minimumConfidence,
            let kind = SoundLabelMap.kind(for: best.identifier)
        else { return }
        let offset = result.timeRange.start.seconds
        let duration = result.timeRange.duration.seconds
        guard offset.isFinite else { return }
        deliver(SoundDetection(
            time: start.addingTimeInterval(offset),
            kind: kind,
            confidence: best.confidence,
            intensity: 0,
            duration: duration.isFinite ? max(0.5, duration) : 1
        ))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}

    func requestDidComplete(_ request: SNRequest) {}
}
#endif
