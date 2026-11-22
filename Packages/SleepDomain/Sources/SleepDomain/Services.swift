import Foundation

/// Accès aux sessions. L'app passe toujours par ce protocole, jamais directement par la base.
public protocol SleepSessionRepository: Sendable {
    /// Les sessions dont la date de référence tombe dans l'intervalle, de la plus récente à la plus ancienne.
    func sessions(in interval: DateInterval?) async throws -> [SleepSession]
    func session(id: UUID) async throws -> SleepSession?
    func save(_ session: SleepSession) async throws
    func delete(id: UUID) async throws
}

/// Journal de diagnostic de l'app, consultable dans les réglages et joint au rapport d'essais.
public protocol DiagnosticJournal: Sendable {
    func record(_ message: String)
    func recentLines(limit: Int) async -> [String]
}

/// Version factice du dépôt, pour les tests et les aperçus.
public actor InMemorySleepSessionRepository: SleepSessionRepository {
    private var storage: [UUID: SleepSession] = [:]

    public init(_ sessions: [SleepSession] = []) {
        for session in sessions {
            storage[session.id] = session
        }
    }

    public func sessions(in interval: DateInterval?) async throws -> [SleepSession] {
        storage.values
            .filter { session in interval.map { $0.contains(session.referenceDate) } ?? true }
            .sorted { $0.referenceDate > $1.referenceDate }
    }

    public func session(id: UUID) async throws -> SleepSession? {
        storage[id]
    }

    public func save(_ session: SleepSession) async throws {
        storage[session.id] = session
    }

    public func delete(id: UUID) async throws {
        storage[id] = nil
    }
}

/// Version factice du journal, pour les tests et les aperçus.
public final class SilentDiagnosticJournal: DiagnosticJournal {
    public init() {}
    public func record(_ message: String) {}
    public func recentLines(limit: Int) async -> [String] { [] }
}
