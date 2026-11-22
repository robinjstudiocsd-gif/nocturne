import Foundation
import OSLog
import SleepDomain

/// Journal de diagnostic écrit dans un fichier texte et dans le journal système (OSLog).
/// Il garde environ 1 Mo ; au-delà, seule la seconde moitié est conservée.
public actor FileDiagnosticJournal: DiagnosticJournal {
    private let fileURL: URL
    private let maximumSize = 1_000_000
    private let logger = Logger(subsystem: "io.github.robinjstudiocsd-gif.nocturne", category: "journal")

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Emplacement par défaut : Application Support/Logs/journal.txt.
    public static func defaultURL() throws -> URL {
        try PersistenceStack.applicationSupportFolder(named: "Logs").appendingPathComponent("journal.txt")
    }

    public nonisolated func record(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let line = Date().formatted(.iso8601) + "  " + message + "\n"
        Task { await self.append(line) }
    }

    public func recentLines(limit: Int) -> [String] {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").suffix(limit).map(String.init)
    }

    private func append(_ line: String) {
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        guard
            let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size > maximumSize,
            let data = try? Data(contentsOf: fileURL)
        else { return }
        var kept = data.suffix(maximumSize / 2)
        if let newline = kept.firstIndex(of: UInt8(ascii: "\n")) {
            kept = kept[kept.index(after: newline)...]
        }
        try? Data(kept).write(to: fileURL, options: .atomic)
    }
}
