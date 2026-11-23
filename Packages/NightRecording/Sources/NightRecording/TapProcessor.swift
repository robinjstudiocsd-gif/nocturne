#if os(iOS)
import AVFoundation
import Foundation

/// Reçoit les blocs du micro, les convertit au format de la nuit et les confie au traitement.
/// Tourne sur le fil du micro, jamais sur celui de l'interface.
final class TapProcessor: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let pipeline: CapturePipeline
    private let deliver: @Sendable (CapturePipeline.Output) -> Void
    private let report: @Sendable (Error) -> Void

    init?(
        inputFormat: AVAudioFormat,
        pipeline: CapturePipeline,
        deliver: @escaping @Sendable (CapturePipeline.Output) -> Void,
        report: @escaping @Sendable (Error) -> Void
    ) {
        guard let converter = AVAudioConverter(from: inputFormat, to: pipeline.processingFormat) else { return nil }
        self.converter = converter
        self.pipeline = pipeline
        self.deliver = deliver
        self.report = report
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        let ratio = pipeline.processingFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: pipeline.processingFormat, frameCapacity: capacity) else { return }
        let input = SingleInput(buffer)
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            guard let next = input.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return next
        }
        guard status != .error, converted.frameLength > 0 else { return }
        do {
            let output = try pipeline.process(converted, at: Date())
            if !output.levels.isEmpty || !output.finishedSegments.isEmpty || !output.events.isEmpty {
                deliver(output)
            }
        } catch {
            report(error)
        }
    }
}

/// Fournit le bloc une seule fois au convertisseur.
private final class SingleInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
#endif
