import Foundation

/// Erreurs des cas d'usage sur les sessions.
public enum SessionError: Error, Equatable, Sendable {
    case notFound
    case notRunning
    case stillRunning
    case invalidTimes([SessionIssue])
}

extension SessionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "Cette nuit n’existe plus."
        case .notRunning:
            return "Cette nuit est déjà terminée."
        case .stillRunning:
            return "Cette nuit est en cours : arrête-la avant de la supprimer."
        case .invalidTimes(let issues):
            if issues.contains(.timesOutOfOrder) {
                return "Les horaires doivent se suivre : coucher, endormissement, réveil, puis lever."
            }
            return "Une nuit ne peut pas durer plus de 24 heures."
        }
    }
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

    /// Toutes les sessions, de la plus récente à la plus ancienne.
    public func sessions() async throws -> [SleepSession] {
        try await repository.sessions(in: nil)
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

    /// Termine une nuit interrompue (app fermée trop longtemps) à la dernière minute connue.
    @discardableResult
    public func close(id: UUID, at end: Date) async throws -> SleepSession {
        guard var session = try await repository.session(id: id) else { throw SessionError.notFound }
        guard session.state == .running else { throw SessionError.notRunning }
        session.detected.wake = end
        session.detected.getUp = end
        session.state = .interrupted
        try await repository.save(session)
        return session
    }

    /// Enregistre ce que l'analyse de la nuit a trouvé : endormissement, réveil et réveils dans la nuit.
    /// Les corrections et les réveils saisis à la main restent ; le lever garde l'heure de l'arrêt.
    @discardableResult
    public func saveDetection(
        id: UUID,
        sleepOnset: Date?,
        wake: Date?,
        wakeEpisodes: [WakeEpisode],
        source: DataSource?,
        analysisVersion: Int
    ) async throws -> SleepSession {
        guard var session = try await repository.session(id: id) else { throw SessionError.notFound }
        if let sleepOnset {
            session.detected.sleepOnset = sleepOnset
        }
        if let wake {
            session.detected.wake = wake
        }
        let typed = session.wakeEpisodes.filter { $0.source == .manual }
        session.wakeEpisodes = (typed + wakeEpisodes).sorted { $0.start < $1.start }
        if let source {
            session.primarySource = source
        }
        session.analysisVersion = analysisVersion
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

    /// Écran « Modifier une nuit » : horaires corrigés, réveils, type, ressenti et commentaire, après vérification.
    @discardableResult
    public func saveEdit(
        id: UUID,
        corrected: SessionTimes,
        wakeEpisodes: [WakeEpisode],
        kind: SessionKind,
        feeling: WakeFeeling?,
        comment: String?
    ) async throws -> SleepSession {
        guard var session = try await repository.session(id: id) else { throw SessionError.notFound }
        session.corrected = corrected
        session.wakeEpisodes = wakeEpisodes.sorted { $0.start < $1.start }
        session.kind = kind
        session.feeling = feeling?.isEmpty == false ? feeling : nil
        session.comment = comment?.trimmedOrNil
        let issues = session.issues
        guard issues.isEmpty else { throw SessionError.invalidTimes(issues) }
        try await repository.save(session)
        return session
    }

    /// Supprime une session et tout ce qui a été enregistré pendant elle. Une session en cours ne se supprime pas.
    public func delete(id: UUID, erasing eraser: any SessionDataEraser) async throws {
        guard let session = try await repository.session(id: id) else { throw SessionError.notFound }
        guard session.state != .running else { throw SessionError.stillRunning }
        try await eraser.eraseRecordings(of: session)
        try await repository.delete(id: id)
    }

    /// Écran « Bonjour » : ressenti, horaires corrigés et commentaire, enregistrés ensemble après vérification.
    @discardableResult
    public func saveMorning(id: UUID, feeling: WakeFeeling?, corrected: SessionTimes, comment: String?) async throws -> SleepSession {
        guard var session = try await repository.session(id: id) else { throw SessionError.notFound }
        session.corrected = corrected
        session.feeling = feeling?.isEmpty == false ? feeling : nil
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
