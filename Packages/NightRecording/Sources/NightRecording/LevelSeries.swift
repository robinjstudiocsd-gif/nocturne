import Foundation

/// Série du niveau sonore d'une nuit, au format binaire compact et versionné.
///
/// Format, version 1 :
/// - 4 octets : « NCLS » ;
/// - 1 octet : version ; 3 octets réservés ;
/// - 8 octets : début de la nuit, en secondes depuis 1970 (Float64, petit-boutiste) ;
/// - puis 2 octets par seconde : moyenne et pic, codés (dB + 120) × 2, 255 signifiant « pas de mesure ».
///
/// Une nuit de 8 h occupe environ 57 Ko.
public struct LevelSeries: Equatable, Sendable {
    public static let magic: [UInt8] = Array("NCLS".utf8)
    public static let version: UInt8 = 1
    public static let headerSize = 16
    public static let missing: UInt8 = 255

    public let start: Date
    /// Une valeur par seconde ; nil quand l'écoute était coupée.
    public let means: [Float?]
    public let peaks: [Float?]

    public init(start: Date, means: [Float?], peaks: [Float?]) {
        self.start = start
        self.means = means
        self.peaks = peaks
    }

    public static func encode(_ db: Float) -> UInt8 {
        let value = ((db + 120) * 2).rounded()
        return UInt8(min(254, max(0, value)))
    }

    public static func decode(_ byte: UInt8) -> Float? {
        byte == missing ? nil : Float(byte) / 2 - 120
    }

    public static func header(start: Date) -> Data {
        var data = Data(magic)
        data.append(version)
        data.append(contentsOf: [0, 0, 0])
        var seconds = start.timeIntervalSince1970.bitPattern.littleEndian
        withUnsafeBytes(of: &seconds) { data.append(contentsOf: $0) }
        return data
    }

    public enum ReadError: Error, Equatable {
        case tooShort
        case badMagic
        case unsupportedVersion(UInt8)
    }

    /// Lit une série depuis le contenu d'un fichier.
    public static func read(_ data: Data) throws -> LevelSeries {
        guard data.count >= headerSize else { throw ReadError.tooShort }
        let bytes = [UInt8](data)
        guard Array(bytes[0..<4]) == magic else { throw ReadError.badMagic }
        guard bytes[4] == version else { throw ReadError.unsupportedVersion(bytes[4]) }
        var bits: UInt64 = 0
        for (offset, byte) in bytes[8..<16].enumerated() {
            bits |= UInt64(byte) << (8 * UInt64(offset))
        }
        let start = Date(timeIntervalSince1970: Double(bitPattern: bits))
        var means: [Float?] = []
        var peaks: [Float?] = []
        var index = headerSize
        while index + 1 < bytes.count {
            means.append(decode(bytes[index]))
            peaks.append(decode(bytes[index + 1]))
            index += 2
        }
        return LevelSeries(start: start, means: means, peaks: peaks)
    }
}

/// Écrit la série du niveau sonore au fil de la nuit, en ajoutant à la fin du fichier.
public final class LevelSeriesWriter {
    public let fileURL: URL
    private var nextSecond = 0
    private var handle: FileHandle?

    /// Crée le fichier et écrit son en-tête.
    public init(fileURL: URL, start: Date) throws {
        self.fileURL = fileURL
        try LevelSeries.header(start: start).write(to: fileURL)
        handle = try FileHandle(forWritingTo: fileURL)
        _ = try handle?.seekToEnd()
    }

    /// Reprend un fichier existant (après une reprise de l'app) : les secondes manquantes seront marquées.
    public init(resuming fileURL: URL) throws {
        self.fileURL = fileURL
        let size = (try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        nextSecond = max(0, (size - LevelSeries.headerSize) / 2)
        handle = try FileHandle(forWritingTo: fileURL)
        _ = try handle?.seekToEnd()
    }

    /// Ajoute des secondes ; un saut de rang est rempli de « pas de mesure ».
    public func append(_ seconds: [LevelSecond]) throws {
        var data = Data()
        for value in seconds where value.second >= nextSecond {
            while nextSecond < value.second {
                data.append(contentsOf: [LevelSeries.missing, LevelSeries.missing])
                nextSecond += 1
            }
            data.append(LevelSeries.encode(value.meanDb))
            data.append(LevelSeries.encode(value.maxDb))
            nextSecond += 1
        }
        guard !data.isEmpty else { return }
        try handle?.write(contentsOf: data)
    }

    public func close() throws {
        try handle?.close()
        handle = nil
    }
}
