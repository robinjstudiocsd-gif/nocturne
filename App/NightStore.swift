import Foundation

/// Résumé d'une nuit enregistrée, relu depuis son dossier.
struct NightSummary {
    let folder: URL
    let start: Date
    let end: Date?
    let segments: Int
    let bytes: Int64
    let interruptions: Int
    let beats: Int
    let gaps: [(Date, Date)]
    let lastBeat: Date?
    let closedNormally: Bool

    var duration: TimeInterval? {
        guard let stop = end ?? lastBeat else { return nil }
        return stop.timeIntervalSince(start)
    }

    /// Battements attendus : un par minute d'écoute.
    var expectedBeats: Int {
        guard let duration else { return 0 }
        return max(0, Int(duration / 60))
    }
}

/// Stockage des nuits : un dossier par nuit dans Documents/Nuits.
enum NightStore {
    static var root: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Nuits", isDirectory: true)
    }

    static func makeNightFolder(start: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let folder = root.appendingPathComponent(formatter.string(from: start), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let marker = ["debut": start.timeIntervalSince1970]
        let data = try JSONSerialization.data(withJSONObject: marker)
        try data.write(to: folder.appendingPathComponent("debut.json"))
        return folder
    }

    static func writeSummary(folder: URL, start: Date, end: Date, segments: Int, bytes: Int64, interruptions: Int) {
        let object: [String: Any] = [
            "debut": start.timeIntervalSince1970,
            "fin": end.timeIntervalSince1970,
            "tranches": segments,
            "octets": bytes,
            "coupures": interruptions
        ]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) {
            try? data.write(to: folder.appendingPathComponent("resume.json"))
        }
    }

    static func allNightFolders() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func latestSummary() -> NightSummary? {
        guard let folder = allNightFolders().first else { return nil }
        return summary(of: folder)
    }

    static func summary(of folder: URL) -> NightSummary? {
        let fm = FileManager.default
        let summaryData = try? Data(contentsOf: folder.appendingPathComponent("resume.json"))
        let summary = summaryData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let startData = try? Data(contentsOf: folder.appendingPathComponent("debut.json"))
        let startObject = startData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }

        guard let startValue = (summary?["debut"] as? Double) ?? (startObject?["debut"] as? Double) else { return nil }
        let start = Date(timeIntervalSince1970: startValue)
        let end = (summary?["fin"] as? Double).map { Date(timeIntervalSince1970: $0) }

        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let audio = files.filter { $0.pathExtension == "m4a" }
        let bytes = audio.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }

        let beatText = (try? String(contentsOf: folder.appendingPathComponent("battements.txt"), encoding: .utf8)) ?? ""
        let beats = beatText.split(separator: "\n").compactMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }.sorted()
        var gaps: [(Date, Date)] = []
        var previous = start
        for beat in beats {
            if beat.timeIntervalSince(previous) > 150 { gaps.append((previous, beat)) }
            previous = beat
        }
        if let end, end.timeIntervalSince(previous) > 150 { gaps.append((previous, end)) }

        return NightSummary(
            folder: folder,
            start: start,
            end: end,
            segments: (summary?["tranches"] as? Int) ?? audio.count,
            bytes: bytes,
            interruptions: (summary?["coupures"] as? Int) ?? 0,
            beats: beats.count,
            gaps: gaps,
            lastBeat: beats.last,
            closedNormally: summary != nil
        )
    }

    static func describe(_ night: NightSummary) -> String {
        var parts: [String] = []
        let stop = night.end ?? night.lastBeat
        parts.append("\(Format.dateTime(night.start)) → \(stop.map { Format.time($0) } ?? "?")")
        if let duration = night.duration { parts.append(Format.duration(duration)) }
        parts.append("\(night.segments) tranches")
        parts.append(Format.size(night.bytes))
        parts.append("battements \(night.beats)/\(night.expectedBeats)")
        parts.append("coupures \(night.interruptions)")
        if night.gaps.isEmpty {
            parts.append("aucun trou")
        } else {
            let list = night.gaps.map { "\(Format.time($0.0))→\(Format.time($0.1))" }.joined(separator: ", ")
            parts.append("trous : \(list)")
        }
        if !night.closedNormally { parts.append("nuit non terminée normalement (app fermée ou arrêtée par iOS)") }
        return parts.joined(separator: " · ")
    }
}
