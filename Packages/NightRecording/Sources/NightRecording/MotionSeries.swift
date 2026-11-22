import Foundation

/// Activité mesurée par l'accéléromètre sur une fenêtre de 30 secondes.
public struct MotionWindow: Equatable, Sendable {
    /// Rang de la fenêtre depuis le début de la nuit.
    public let index: Int
    /// Écart moyen à la gravité, en milli-g : 0 quand l'iPhone ne bouge pas.
    public let activity: Float

    public init(index: Int, activity: Float) {
        self.index = index
        self.activity = activity
    }
}

/// Regroupe les mesures de l'accéléromètre par fenêtres de 30 secondes.
public struct MotionAccumulator: Sendable {
    public static let windowDuration: TimeInterval = 30

    private let start: Date
    private var window = 0
    private var total: Double = 0
    private var count = 0

    public init(start: Date) {
        self.start = start
    }

    /// Ajoute une mesure (accélération en g) ; renvoie les fenêtres terminées.
    public mutating func add(x: Double, y: Double, z: Double, at time: Date) -> [MotionWindow] {
        var finished: [MotionWindow] = []
        let index = max(0, Int(time.timeIntervalSince(start) / MotionAccumulator.windowDuration))
        if index > window {
            if count > 0 {
                finished.append(MotionWindow(index: window, activity: Float(total / Double(count))))
            }
            window = index
            total = 0
            count = 0
        }
        let magnitude = (x * x + y * y + z * z).squareRoot()
        total += abs(magnitude - 1) * 1_000
        count += 1
        return finished
    }

    /// Termine la fenêtre en cours.
    public mutating func flush() -> MotionWindow? {
        guard count > 0 else { return nil }
        let result = MotionWindow(index: window, activity: Float(total / Double(count)))
        window += 1
        total = 0
        count = 0
        return result
    }
}

/// Série des mouvements d'une nuit : « NCMS », version, début, puis un octet par fenêtre de 30 s
/// (activité en milli-g divisée par 2, 255 pour « pas de mesure »).
public enum MotionSeries {
    public static let magic: [UInt8] = Array("NCMS".utf8)
    public static let version: UInt8 = 1
    public static let missing: UInt8 = 255

    public static func encode(_ activity: Float) -> UInt8 {
        UInt8(min(254, max(0, (activity / 2).rounded())))
    }

    public static func decode(_ byte: UInt8) -> Float? {
        byte == missing ? nil : Float(byte) * 2
    }

    public static func header(start: Date) -> Data {
        var data = Data(magic)
        data.append(version)
        data.append(contentsOf: [0, 0, 0])
        var seconds = start.timeIntervalSince1970.bitPattern.littleEndian
        withUnsafeBytes(of: &seconds) { data.append(contentsOf: $0) }
        return data
    }

    /// Lit les fenêtres d'un fichier (nil pour une fenêtre sans mesure).
    public static func read(_ data: Data) -> [Float?]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 16, Array(bytes[0..<4]) == magic, bytes[4] == version else { return nil }
        return bytes[16...].map { decode($0) }
    }
}

/// Écrit la série des mouvements au fil de la nuit.
public final class MotionSeriesWriter {
    private var handle: FileHandle?
    private var nextIndex = 0

    public init(fileURL: URL, start: Date) throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let size = (try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 16
            nextIndex = max(0, size - 16)
        } else {
            try MotionSeries.header(start: start).write(to: fileURL)
        }
        handle = try FileHandle(forWritingTo: fileURL)
        _ = try handle?.seekToEnd()
    }

    public func append(_ windows: [MotionWindow]) throws {
        var data = Data()
        for window in windows where window.index >= nextIndex {
            while nextIndex < window.index {
                data.append(MotionSeries.missing)
                nextIndex += 1
            }
            data.append(MotionSeries.encode(window.activity))
            nextIndex += 1
        }
        guard !data.isEmpty else { return }
        try handle?.write(contentsOf: data)
    }

    public func close() throws {
        try handle?.close()
        handle = nil
    }
}
