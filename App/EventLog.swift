import Foundation

/// Journal de diagnostic de la phase 0, gardé dans un fichier texte de l'app.
final class EventLog: ObservableObject {
    static let shared = EventLog()

    @Published private(set) var recent: [String] = []

    let fileURL: URL
    private let queue = DispatchQueue(label: "nocturne.journal")
    private let formatter: DateFormatter

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("journal-phase0.txt")
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            recent = text.split(separator: "\n").suffix(150).map(String.init)
        }
    }

    func add(_ message: String) {
        let line = formatter.string(from: Date()) + "  " + message
        let url = fileURL
        queue.async {
            let data = Data((line + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        DispatchQueue.main.async {
            self.recent.append(line)
            if self.recent.count > 150 {
                self.recent.removeFirst(self.recent.count - 150)
            }
        }
    }

    /// Les dernières lignes du fichier, pour le rapport.
    func lastLines(_ count: Int) -> [String] {
        let url = fileURL
        return queue.sync {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return text.split(separator: "\n").suffix(count).map(String.init)
        }
    }
}
