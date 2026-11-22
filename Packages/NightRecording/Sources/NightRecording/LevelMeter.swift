import Foundation

/// Niveau sonore d'une seconde : moyenne énergétique et pic, en dB relatifs à la pleine échelle.
public struct LevelSecond: Equatable, Sendable {
    /// Rang de la seconde depuis le début de la nuit.
    public let second: Int
    public let meanDb: Float
    public let maxDb: Float

    public init(second: Int, meanDb: Float, maxDb: Float) {
        self.second = second
        self.meanDb = meanDb
        self.maxDb = maxDb
    }
}

/// Calcule le niveau sonore seconde par seconde à partir des échantillons du micro.
/// Le niveau est relatif (dBFS) : le micro de l'iPhone n'est pas étalonné.
public struct LevelMeter: Sendable {
    public static let silence: Float = -120

    private let sampleRate: Double
    private var second = 0
    private var samplesInSecond = 0
    private var energyInSecond: Double = 0
    private var peakInSecond: Float = LevelMeter.silence

    public init(sampleRate: Double, startingSecond: Int = 0) {
        self.sampleRate = sampleRate
        self.second = startingSecond
    }

    /// Niveau d'un bloc d'échantillons, en dBFS.
    public static func decibels(rms: Double) -> Float {
        rms > 0.000_001 ? Float(20 * log10(rms)) : silence
    }

    /// Ajoute un bloc d'échantillons ; renvoie les secondes terminées.
    public mutating func add(_ samples: UnsafeBufferPointer<Float>) -> [LevelSecond] {
        var finished: [LevelSecond] = []
        let perSecond = max(1, Int(sampleRate.rounded()))
        var index = 0
        while index < samples.count {
            let take = min(samples.count - index, perSecond - samplesInSecond)
            var energy: Double = 0
            for offset in index..<(index + take) {
                let value = Double(samples[offset])
                energy += value * value
            }
            let blockDb = LevelMeter.decibels(rms: (energy / Double(take)).squareRoot())
            energyInSecond += energy
            samplesInSecond += take
            peakInSecond = max(peakInSecond, blockDb)
            index += take
            if samplesInSecond >= perSecond {
                finished.append(closeSecond())
            }
        }
        return finished
    }

    /// Variante pratique pour les tableaux.
    public mutating func add(_ samples: [Float]) -> [LevelSecond] {
        samples.withUnsafeBufferPointer { add($0) }
    }

    /// Termine la seconde en cours si elle contient des échantillons.
    public mutating func flush() -> LevelSecond? {
        samplesInSecond > 0 ? closeSecond() : nil
    }

    /// Saute des secondes sans échantillons (trou d'enregistrement).
    public mutating func skip(to second: Int) {
        guard second > self.second else { return }
        self.second = second
        samplesInSecond = 0
        energyInSecond = 0
        peakInSecond = LevelMeter.silence
    }

    private mutating func closeSecond() -> LevelSecond {
        let mean = LevelMeter.decibels(rms: (energyInSecond / Double(max(1, samplesInSecond))).squareRoot())
        let result = LevelSecond(second: second, meanDb: mean, maxDb: max(mean, peakInSecond))
        second += 1
        samplesInSecond = 0
        energyInSecond = 0
        peakInSecond = LevelMeter.silence
        return result
    }
}
