import Foundation
import SleepDomain

/// Ce que l'accueil, la fiche de nuit et « Bonjour » montrent d'une nuit : score, qualité, fiabilité
/// et comparaison avec la moyenne des nuits précédentes.
public struct NightReport: Sendable {
    public var score: ScoreBreakdown
    public var quality: SleepQuality?
    /// Fiabilité affichée : celle du score, sinon celle des horaires.
    public var reliability: Reliability
    /// Nuits précédentes qui servent à la comparaison (7 au plus).
    public var previousNights: Int
    public var averages: NightAverages
    public var comparison: NightComparison
    /// Score moyen des nuits précédentes qui en ont un.
    public var averageScore: Double?

    /// « Fiabilité moyenne »
    public var reliabilityText: String {
        "Fiabilité \(reliability.title)"
    }
}

/// Construit le rapport d'une nuit à partir de toutes les sessions connues.
public struct NightReporter: Sendable {
    /// Nombre de nuits précédentes comparées (étude : « moyenne sur 7 nuits »).
    public static let comparedNights = 7

    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func report(for session: SleepSession, among sessions: [SleepSession], goals: ScoreGoals = ScoreGoals()) -> NightReport {
        let scorer = SleepScorer(calendar: calendar)
        let score = scorer.score(ScoreInput(session: session, previousNights: sessions, goals: goals))
        let previous = Self.previousNights(of: session, among: sessions)
        let averages = NightAverages(sessions: previous, calendar: calendar)
        let scores = previous.compactMap { night in
            scorer.score(ScoreInput(session: night, previousNights: sessions, goals: goals)).total
        }
        return NightReport(
            score: score,
            quality: scorer.quality(of: session),
            reliability: score.reliability ?? session.timesReliability,
            previousNights: previous.count,
            averages: averages,
            comparison: NightComparison(session: session, previous: averages, calendar: calendar),
            averageScore: scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count)
        )
    }

    /// Les nuits terminées juste avant celle-ci, de la plus récente à la plus ancienne.
    public static func previousNights(of session: SleepSession, among sessions: [SleepSession], limit: Int = comparedNights) -> [SleepSession] {
        let reference = session.referenceDate
        return Array(
            sessions
                .filter { $0.kind == .night && $0.state != .running && $0.id != session.id && $0.referenceDate < reference }
                .sorted { $0.referenceDate > $1.referenceDate }
                .prefix(limit)
        )
    }
}

/// Textes des écarts : « +40 min », « −1 h 47 », « −6 ».
public enum DifferenceText {
    /// Signe moins typographique, comme dans les maquettes.
    public static let minus = "\u{2212}"

    public static func duration(_ seconds: TimeInterval, format: SleepFormat) -> String {
        let rounded = (seconds / 60).rounded() * 60
        guard rounded != 0 else { return "=" }
        return (rounded > 0 ? "+" : minus) + format.duration(abs(rounded))
    }

    public static func points(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        guard rounded != 0 else { return "=" }
        return rounded > 0 ? "+\(rounded)" : "\(minus)\(-rounded)"
    }
}
