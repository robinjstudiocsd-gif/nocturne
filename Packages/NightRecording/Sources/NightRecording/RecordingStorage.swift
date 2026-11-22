import Foundation

/// Emplacements des fichiers de l'écoute, dans Application Support.
public struct RecordingStorage: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Dossier Application Support de l'app.
    public static func applicationSupport() throws -> RecordingStorage {
        let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return RecordingStorage(root: url)
    }

    /// Crée le dossier d'une nuit. L'audio est protégé « sauf si ouvert » :
    /// il s'écrit écran verrouillé, mais ne se relit qu'iPhone déverrouillé.
    public func prepareFolder(for layout: SegmentLayout) throws -> URL {
        let folder = root.appendingPathComponent(layout.relativeFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: folder.path)
        #endif
        return folder
    }

    /// Fichier du point de reprise, lisible dès le premier déverrouillage après un redémarrage.
    public var checkpointURL: URL {
        root.appendingPathComponent("reprise-nuit.json")
    }

    public func url(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    /// Taille totale des fichiers d'une nuit.
    public func size(of layout: SegmentLayout) -> Int64 {
        let folder = root.appendingPathComponent(layout.relativeFolder, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
