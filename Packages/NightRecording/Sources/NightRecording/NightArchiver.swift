import Foundation
import SleepDomain

/// Archives sans cloud (étude, « Archives vers le PC ») : une nuit complète devient un fichier .zip
/// dans le dossier Documents de l'app, visible dans l'app Fichiers et dans le partage de fichiers
/// d'Appareils Apple ou d'iTunes sur Windows. Il contient l'audio, la liste des événements (CSV pour Excel)
/// et un résumé lisible.
public struct NightArchiver: Sendable {
    private let storage: RecordingStorage
    private let recordings: any RecordingRepository
    private let events: any NightEventRepository
    private let documents: URL
    private let calendar: Calendar

    public init(
        storage: RecordingStorage,
        recordings: any RecordingRepository,
        events: any NightEventRepository,
        documents: URL,
        calendar: Calendar = .current
    ) {
        self.storage = storage
        self.recordings = recordings
        self.events = events
        self.documents = documents
        self.calendar = calendar
    }

    /// Le dossier Documents de l'app, partagé avec l'app Fichiers et le PC.
    public static func documentsFolder() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    /// Dossier des archives.
    public var folder: URL {
        documents.appendingPathComponent("Archives", isDirectory: true)
    }

    /// Crée (ou remplace) l'archive d'une nuit et renvoie son adresse.
    public func archive(_ session: SleepSession, eveningLog: EveningLog? = nil) async throws -> URL {
        let segments = try await recordings.segments(sessionID: session.id).sorted { $0.start < $1.start }
        let gaps = try await recordings.gaps(sessionID: session.id)
        let nightEvents = try await events.events(sessionID: session.id)
        let name = Self.fileName(NightCalendar(calendar: calendar).title(of: session))

        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appendingPathComponent("Archive-\(UUID().uuidString)", isDirectory: true)
        let content = staging.appendingPathComponent(name, isDirectory: true)
        let audio = content.appendingPathComponent("audio", isDirectory: true)
        try manager.createDirectory(at: audio, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        let format = SleepFormat(calendar: calendar)
        for segment in segments {
            let source = storage.url(for: segment.relativePath)
            guard manager.fileExists(atPath: source.path) else { continue }
            let target = audio.appendingPathComponent("\(format.clock(segment.start).replacingOccurrences(of: ":", with: "h")) - \(source.lastPathComponent)")
            try? manager.removeItem(at: target)
            try manager.copyItem(at: source, to: target)
        }
        // Marque d'encodage en tête : Excel sous Windows lit alors correctement les accents.
        try Data(("\u{FEFF}" + Self.eventsCSV(nightEvents, format: format)).utf8).write(to: content.appendingPathComponent("evenements.csv"))
        try Data(Self.summary(session, gaps: gaps, events: nightEvents, segments: segments, eveningLog: eveningLog, calendar: calendar).utf8)
            .write(to: content.appendingPathComponent("resume.txt"))

        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("\(name).zip")
        try Self.zip(content, to: destination)
        return destination
    }

    /// Nom de fichier sans caractères gênants pour Windows.
    static func fileName(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return title.components(separatedBy: forbidden).joined(separator: "-")
    }

    /// Liste des événements pour Excel : séparateur point-virgule, virgule décimale.
    public static func eventsCSV(_ events: [NightEvent], format: SleepFormat) -> String {
        var lines = ["Heure;Type;Durée (s);Confiance;Intensité;Pas moi;Favori;Extrait"]
        for event in events.sorted(by: { $0.start < $1.start }) {
            let parts = format.calendar.dateComponents([.hour, .minute, .second], from: event.start)
            let clock = String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
            let duration = String(format: "%.1f", event.duration).replacingOccurrences(of: ".", with: ",")
            let fields = [
                clock,
                event.kind.title,
                duration,
                "\(Int((event.confidence * 100).rounded())) %",
                event.intensity >= 20 ? "forte" : (event.intensity >= 10 ? "moyenne" : "faible"),
                event.isSomeoneElse ? "oui" : "non",
                event.isFavorite ? "oui" : "non",
                event.clipPath.map { ($0 as NSString).lastPathComponent } ?? ""
            ]
            lines.append(fields.joined(separator: ";"))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Résumé lisible de la nuit.
    public static func summary(
        _ session: SleepSession,
        gaps: [RecordingGap],
        events: [NightEvent],
        segments: [AudioSegment],
        eveningLog: EveningLog?,
        calendar: Calendar
    ) -> String {
        let text = NightDetailText(calendar: calendar)
        let format = text.format
        let times = session.times
        func clock(_ date: Date?) -> String { date.map(format.clock) ?? "—" }
        var lines = [NightCalendar(calendar: calendar).title(of: session), ""]
        lines.append("Horaires")
        lines.append("  Coucher : \(clock(times.bedtime))")
        lines.append("  Endormissement : \(clock(times.sleepOnset))")
        lines.append("  Réveil : \(clock(times.wake))")
        lines.append("  Lever : \(clock(times.getUp))")
        if let asleep = session.asleepDuration {
            lines.append("  Sommeil : \(format.duration(asleep))")
        }
        if let inBed = session.timeInBed {
            lines.append("  Au lit : \(format.duration(inBed))")
        }
        lines.append("")
        lines.append("Écoute")
        let bytes = segments.reduce(0) { $0 + $1.byteSize }
        lines.append("  \(text.listening(session, gaps: gaps, bytes: bytes, now: Date()))")
        for gap in gaps {
            lines.append("  \(text.gap(gap))")
        }
        let mine = events.filter { !$0.isSomeoneElse }
        if !mine.isEmpty {
            lines.append("")
            lines.append("Événements")
            for kind in EventKind.allCases {
                let ofKind = mine.filter { $0.kind == kind }
                guard !ofKind.isEmpty else { continue }
                let total = ofKind.reduce(0) { $0 + $1.duration }
                lines.append("  \(kind.pluralTitle) : \(ofKind.count), \(format.span(total))")
            }
        }
        if let feeling = session.feeling {
            lines.append("")
            lines.append("Ressenti")
            if let mood = feeling.mood {
                lines.append("  Humeur : \(WakeFeeling.moodLabel(mood))")
            }
            if let energy = feeling.energy {
                lines.append("  Énergie : \(energy) sur 5")
            }
        }
        if let log = eveningLog {
            let rows = [
                ("Caféine", text.caffeine(log)), ("Sport", text.exercise(log)), ("Écrans", text.screens(log)),
                ("Stress", text.stress(log)), ("Repas", text.meal(log)), ("Note", log.note)
            ].compactMap { label, value in value.map { "  \(label) : \($0)" } }
            if !rows.isEmpty {
                lines.append("")
                lines.append("Journal du soir")
                lines += rows
            }
        }
        if let comment = session.comment {
            lines.append("")
            lines.append("Commentaire : \(comment)")
        }
        lines.append("")
        lines.append("Archivé par Nocturne. Les niveaux sonores sont relatifs, sans étalonnage. Ce n’est pas un diagnostic médical.")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Compresse un dossier en .zip avec le service d'iOS (aucune bibliothèque extérieure).
    static func zip(_ folder: URL, to destination: URL) throws {
        var coordination: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordination) { zipped in
            do {
                let manager = FileManager.default
                if manager.fileExists(atPath: destination.path) {
                    try manager.removeItem(at: destination)
                }
                try manager.copyItem(at: zipped, to: destination)
            } catch {
                failure = error
            }
        }
        if let error = coordination ?? failure {
            throw error
        }
    }
}
