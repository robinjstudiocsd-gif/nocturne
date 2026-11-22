import AVFoundation

/// Sonnerie de test générée par le code : trois notes douces qui se répètent.
enum AlarmTone {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    static func makeBuffer() -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = Int(sampleRate * 2.4)
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
            let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let notes: [(start: Double, frequency: Double)] = [(0.0, 659.25), (0.45, 880.0), (0.9, 987.77)]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            var value = 0.0
            for note in notes where time >= note.start {
                let elapsed = time - note.start
                let envelope = exp(-elapsed * 3.2) * min(1, elapsed * 200)
                value += sin(2 * Double.pi * note.frequency * elapsed) * envelope * 0.3
            }
            channel[index] = Float(value)
        }
        return buffer
    }
}
