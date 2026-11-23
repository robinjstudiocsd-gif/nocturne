import Foundation
import SleepDomain

/// Efface tout ce qu'une nuit a enregistré : tranches audio, extraits, niveaux, mouvements,
/// puis leurs fiches et les événements dans la base.
public struct RecordingEraser: SessionDataEraser {
    private let storage: RecordingStorage
    private let recordings: any RecordingRepository
    private let events: any NightEventRepository

    public init(storage: RecordingStorage, recordings: any RecordingRepository, events: any NightEventRepository) {
        self.storage = storage
        self.recordings = recordings
        self.events = events
    }

    public func eraseRecordings(of session: SleepSession) async throws {
        try storage.removeFolders(sessionID: session.id)
        try await recordings.deleteAll(sessionID: session.id)
        try await events.deleteAll(sessionID: session.id)
    }
}

extension RecordingStorage {
    /// Supprime le dossier d'une nuit, quel que soit le jour sous lequel il est rangé,
    /// puis le dossier du jour s'il est devenu vide.
    public func removeFolders(sessionID: UUID) throws {
        let manager = FileManager.default
        let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
        guard let days = try? manager.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil) else { return }
        for day in days {
            let folder = day.appendingPathComponent(sessionID.uuidString, isDirectory: true)
            guard manager.fileExists(atPath: folder.path) else { continue }
            try manager.removeItem(at: folder)
            if let rest = try? manager.contentsOfDirectory(atPath: day.path), rest.isEmpty {
                try? manager.removeItem(at: day)
            }
        }
    }
}
