import Foundation
import Observation
import SleepDomain

/// Modèle de vue du Journal : la liste des nuits enregistrées.
@MainActor
@Observable
public final class JournalViewModel {
    public private(set) var sessions: [SleepSession] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let repository: any SleepSessionRepository

    public init(repository: any SleepSessionRepository) {
        self.repository = repository
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await repository.sessions(in: nil)
            errorMessage = nil
        } catch {
            errorMessage = "Impossible de lire tes nuits : \(error.localizedDescription)"
        }
    }

    /// Titre d'une ligne du journal, par exemple « Nuit du sam. 21 nov. ».
    public func title(for session: SleepSession) -> String {
        let day = session.referenceDate.formatted(
            Date.FormatStyle(locale: Locale(identifier: "fr_FR")).weekday(.abbreviated).day().month(.abbreviated)
        )
        return session.kind == .nap ? "Sieste du \(day)" : "Nuit du \(day)"
    }
}
