import Foundation

/// Erreurs des cas d'usage sur les sessions.
public enum SessionError: Error, Equatable, Sendable {
    case notFound
    case notRunning
    case invalidTimes([SessionIssue])
}

/// Cas d'usage d'une session sans audio (lot 1) : démarrer, arrêter, saisir, corriger.
/// L'écoute de la nuit s'y branchera au lot 2.
public struct SessionLifecycle: Sendable {
    private let repository: any SleepSessionRepository
    private let now: @Sendable () -> Date

    public init(repository: any SleepSessionRepository, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    /// La session en cours, s'il y en a une.
    public func running() async throws -> SleepSession? {
        try await repository.sessions(in: nil).first { $0.state == .running }
    }

    /// Démarre une nuit ou une sieste. Jamais deux sessions en cours : on reprend celle qui existe.
    @discardableResult
    public func start(kind: SessionKind, mode: RecordingMode) async throws -> SleepSession {
        if let current = try await running() {
            return current
        }
        let session = SleepSession(
            kind: kind,
            state: .running,
            detected: SessionTimes(bedtime: now()),
            primarySource: .manual,
            recordingMode: mode,
            createdAt: now()
        )
        try await repository.save(session)
        return session
    }

    /// Arrête la session : le réveil et le lever prennent l'heure actuelle.
    @discardableResult
    public func stop(id: UUID) async throws -> SleepSession {
        guard var session = try await repository.session(id: id) else { throw SessionError.notFound }
        guard session.state == .running else { throw SessionError.notRunning }
        let time = now()
        session.detected.wake = time
        session.detected.getUp = time
        session.state = .finished
        try await repository.save(session)
        return session
    }

    /// Enregistre une nuit ou une sieste saisie à la main, après vérification des horaires.
    @discardableResult
    public func addManual(kind: SessionKind, times: SessionTimes, comment: String?) async throws -> SleepSession {
        let session = SleepSession(
            kind: kind,
            state: .manual,
            detected: times,
            primarySource: .manual,
            recordingMode: .off,
            comment: comment?.trimmedOrNil,
            createdAt: now()
        )
        let issues = session.issues
        guard issues.isEmpty else { throw SessionError.invalidTimes(issues) }
        try await repository.save(session)
        return session
    }

    /// Enregistre une correction. La détection d'origine n'est jamais modifiée.
    @discardableResult
    public func applyCorrection(id: UUID, corrected: SessionTimes, wakeEpisodes: [WakeEpisode], kind: SessionKind, comment: String?) async throws -> SleepSession {
        guard var session = try await repository.session(id: id) else { throw SessionError.notFound }
        session.corrected = corrected
        session.wakeEpisodes = wakeEpisodes.sorted { $0.start < $1.start }
        session.kind = kind
        session.comment = comment?.trimmedOrNil
        let issues = session.issues
        guard issues.isEmpty else { throw SessionError.invalidTimes(issues) }
        try await repository.save(session)
        return session
    }

    /// Enregistre le ressenti du réveil et, au besoin, un commentaire.
    @discardableResult
    public func recordFeeling(_ feeling: WakeFeeling, comment: String?, id: UUID) async throws -> SleepSession {
        guard var session = try await repository.session(id: id) else { throw SessionError.notFound }
        session.feeling = feeling
        if let comment = comment?.trimmedOrNil {
            session.comment = comment
        }
        try await repository.save(session)
        return session
    }

    public func delete(id: UUID) async throws {
        try await repository.delete(id: id)
    }
}

extension String {
    /// Le texte sans espaces autour, ou nil s'il est vide.
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
