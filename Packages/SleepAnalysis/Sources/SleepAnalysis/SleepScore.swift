import Foundation
import SleepDomain

/// Fiabilité d'une donnée ou d'un résultat.
public enum Reliability: Int, Comparable, Codable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: Reliability, rhs: Reliability) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .low: "faible"
        case .medium: "moyenne"
        case .high: "élevée"
        }
    }

    /// Un niveau plus bas, sans descendre sous « faible ».
    var lowered: Reliability {
        Reliability(rawValue: max(0, rawValue - 1)) ?? .low
    }
}

extension SleepSession {
    /// Fiabilité des horaires retenus (METHODOLOGIE-SCORE.md) : élevée avec une montre, moyenne avec l'iPhone
    /// sur le lit ou des horaires saisis ou corrigés par la personne, faible avec le son seul.
    public var timesReliability: Reliability {
        if primarySource == .watch {
            return .high
        }
        if corrected.sleepOnset != nil || corrected.wake != nil {
            return .medium
        }
        switch primarySource {
        case .watch: return .high
        case .motion, .manual: return .medium
        case .microphone: return .low
        }
    }
}

/// Les six critères du score (étude, « Score de sommeil sur 100 »).
public enum ScoreCriterion: String, CaseIterable, Codable, Sendable {
    case duration
    case continuity
    case awakenings
    case regularity
    case stages
    case goals

    public var weight: Double {
        switch self {
        case .duration: 30
        case .continuity: 20
        case .awakenings: 10
        case .regularity: 20
        case .stages: 10
        case .goals: 10
        }
    }

    public var title: String {
        switch self {
        case .duration: "Durée"
        case .continuity: "Continuité"
        case .awakenings: "Réveils"
        case .regularity: "Régularité"
        case .stages: "Phases"
        case .goals: "Objectifs personnels"
        }
    }
}

/// Note d'un critère : disponible ou non, avec sa valeur, sa fiabilité et ses points.
public struct CriterionScore: Equatable, Codable, Sendable {
    public var criterion: ScoreCriterion
    /// Note entre 0 et 1, ou nil si le critère est retiré du calcul.
    public var note: Double?
    public var reliability: Reliability?
    /// La mesure, en clair (« 7 h 12 », « 2 réveils »).
    public var value: String?
    /// Pourquoi le critère manque, s'il manque.
    public var missing: String?
    /// Points gagnés sur 100, une fois les poids redistribués.
    public var points: Double
    /// Points possibles sur 100, une fois les poids redistribués.
    public var maxPoints: Double

    public var isCounted: Bool {
        note != nil
    }
}

/// Détail du score d'une nuit, recalculé après chaque correction.
public struct ScoreBreakdown: Equatable, Codable, Sendable {
    /// Version de la formule, gardée avec chaque nuit (METHODOLOGIE-SCORE.md).
    public static let formulaVersion = 1

    public var version: Int
    public var criteria: [CriterionScore]
    /// Score sur 100, ou nil : « Score indisponible ».
    public var total: Int?
    public var reliability: Reliability?
    /// Vrai si la fiabilité est faible : score arrondi à 5 points et précédé de « environ ».
    public var isApproximate: Bool
    /// Poids des critères comptés, sur 100.
    public var countedWeight: Double

    /// « 83 », « environ 85 », « Score indisponible ».
    public var displayText: String {
        guard let total else { return "Score indisponible" }
        return isApproximate ? "environ \(total)" : "\(total)"
    }

    /// Les données qui manquent, pour l'écran « Score indisponible ».
    public var missing: [String] {
        criteria.compactMap { score in score.missing.map { "\(score.criterion.title) : \($0)" } }
    }
}

/// Qualité estimée de la nuit : continuité et réveils seulement.
public enum SleepQuality: String, Codable, Sendable {
    case veryGood
    case good
    case fair
    case poor

    public var title: String {
        switch self {
        case .veryGood: "très bonne"
        case .good: "bonne"
        case .fair: "moyenne"
        case .poor: "faible"
        }
    }
}

/// Objectifs utilisés par le score.
public struct ScoreGoals: Equatable, Sendable {
    /// Durée de sommeil visée (7 à 9 h par défaut, recommandation NSF).
    public var duration: ClosedRange<TimeInterval>
    public var bedtime: ClockTime?
    public var getUp: ClockTime?

    public init(duration: ClosedRange<TimeInterval> = (7 * 3_600)...(9 * 3_600), bedtime: ClockTime? = nil, getUp: ClockTime? = nil) {
        self.duration = duration
        self.bedtime = bedtime
        self.getUp = getUp
    }
}

/// Phases mesurées par la montre, pour le critère « Phases ».
public struct StageShares: Equatable, Sendable {
    /// Part du profond et du paradoxal dans le sommeil, de 0 à 1.
    public var deepAndREM: Double
    /// Ta médiane sur 30 nuits, de 0 à 1.
    public var personalMedian: Double
    /// Nuits mesurées par la montre.
    public var measuredNights: Int

    public init(deepAndREM: Double, personalMedian: Double, measuredNights: Int) {
        self.deepAndREM = deepAndREM
        self.personalMedian = personalMedian
        self.measuredNights = measuredNights
    }
}

/// Ce que le score regarde pour une nuit.
public struct ScoreInput: Sendable {
    public var session: SleepSession
    /// Nuits précédentes, pour la régularité (les 7 dernières servent).
    public var previousNights: [SleepSession]
    /// Fiabilité des horaires de la nuit (détection du téléphone, montre, saisie) ; par défaut, celle de la session.
    public var timesReliability: Reliability
    /// Phases de la montre ; nil sans montre (l'estimation expérimentale n'entre jamais dans le score).
    public var stages: StageShares?
    public var goals: ScoreGoals

    public init(session: SleepSession, previousNights: [SleepSession] = [], timesReliability: Reliability? = nil, stages: StageShares? = nil, goals: ScoreGoals = ScoreGoals()) {
        self.session = session
        self.previousNights = previousNights
        self.timesReliability = timesReliability ?? session.timesReliability
        self.stages = stages
        self.goals = goals
    }
}

/// Calcul du score sur 100 : six critères pondérés ; un critère sans données fiables est retiré
/// et son poids redistribué ; sous 60 points de critères, pas de score.
public struct SleepScorer: Sendable {
    public let calendar: Calendar
    private let format: SleepFormat

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.format = SleepFormat(calendar: calendar)
    }

    /// Note linéaire : 1 à `best`, 0 à `worst`, proportionnelle entre les deux.
    public static func linear(_ value: Double, best: Double, worst: Double) -> Double {
        if best < worst {
            if value <= best { return 1 }
            if value >= worst { return 0 }
            return (worst - value) / (worst - best)
        }
        if value >= best { return 1 }
        if value <= worst { return 0 }
        return (value - worst) / (best - worst)
    }

    public func score(_ input: ScoreInput) -> ScoreBreakdown {
        var notes: [(ScoreCriterion, Double?, String?, String?)] = [
            duration(input),
            continuity(input),
            awakenings(input),
            regularity(input),
            stages(input),
            goals(input)
        ]
        // Seules les données d'une fiabilité au moins moyenne comptent.
        if input.timesReliability < .medium {
            notes = notes.map { entry -> (ScoreCriterion, Double?, String?, String?) in
                if entry.0 == .stages || entry.1 == nil {
                    return entry
                }
                return (entry.0, nil, entry.2, "horaires trop peu fiables")
            }
        }
        let counted = notes.filter { $0.1 != nil }
        let weight = counted.reduce(0) { $0 + $1.0.weight }
        let criteria = notes.map { entry -> CriterionScore in
            let (criterion, note, value, missing) = entry
            let share = weight > 0 && note != nil ? 100 * criterion.weight / weight : 0
            return CriterionScore(
                criterion: criterion,
                note: note,
                reliability: note == nil ? nil : (criterion == .stages ? .high : input.timesReliability),
                value: value,
                missing: note == nil ? missing : nil,
                points: share * (note ?? 0),
                maxPoints: share
            )
        }
        guard weight >= 60 else {
            return ScoreBreakdown(version: ScoreBreakdown.formulaVersion, criteria: criteria, total: nil, reliability: nil, isApproximate: false, countedWeight: weight)
        }
        let raw = criteria.reduce(0) { $0 + $1.points }
        var reliability = criteria.compactMap(\.reliability).min() ?? .medium
        if weight < 80 {
            reliability = reliability.lowered
        }
        let approximate = reliability == .low
        let total = approximate ? Int((raw / 5).rounded()) * 5 : Int(raw.rounded())
        return ScoreBreakdown(
            version: ScoreBreakdown.formulaVersion,
            criteria: criteria,
            total: min(100, max(0, total)),
            reliability: reliability,
            isApproximate: approximate,
            countedWeight: weight
        )
    }

    /// Qualité estimée : continuité (deux tiers) et réveils (un tiers).
    public func quality(of session: SleepSession) -> SleepQuality? {
        let input = ScoreInput(session: session)
        let parts = [(continuity(input).1, 20.0), (awakenings(input).1, 10.0)].compactMap { note, weight in note.map { ($0, weight) } }
        guard !parts.isEmpty else { return nil }
        let value = parts.reduce(0) { $0 + $1.0 * $1.1 } / parts.reduce(0) { $0 + $1.1 }
        if value >= 0.85 { return .veryGood }
        if value >= 0.7 { return .good }
        if value >= 0.5 { return .fair }
        return .poor
    }

    // MARK: - Critères

    private func duration(_ input: ScoreInput) -> (ScoreCriterion, Double?, String?, String?) {
        guard let asleep = input.session.asleepDuration else {
            return (.duration, nil, nil, "heure d’endormissement ou de réveil inconnue")
        }
        let range = input.goals.duration
        let note: Double
        if asleep < range.lowerBound {
            note = Self.linear(asleep, best: range.lowerBound, worst: range.lowerBound - 2 * 3_600)
        } else if asleep > range.upperBound {
            note = Self.linear(asleep, best: range.upperBound, worst: range.upperBound + 2 * 3_600)
        } else {
            note = 1
        }
        return (.duration, note, format.duration(asleep), nil)
    }

    private func continuity(_ input: ScoreInput) -> (ScoreCriterion, Double?, String?, String?) {
        let session = input.session
        guard session.sleepWindow != nil else {
            return (.continuity, nil, nil, "heure d’endormissement ou de réveil inconnue")
        }
        let waso = Self.linear(session.wakeDuration / 60, best: 20, worst: 60)
        // Sans heure de coucher, la continuité ne repose que sur l'éveil après endormissement.
        guard let asleep = session.asleepDuration, let inBed = session.timeInBed, inBed > 0, let latency = session.sleepLatency else {
            return (.continuity, waso, "éveil \(format.duration(session.wakeDuration))", nil)
        }
        let efficiency = asleep / inBed
        let parts = [
            Self.linear(efficiency, best: 0.85, worst: 0.65),
            waso,
            Self.linear(latency / 60, best: 30, worst: 60)
        ]
        return (.continuity, parts.reduce(0, +) / 3, "efficacité \(Int((efficiency * 100).rounded())) %", nil)
    }

    private func awakenings(_ input: ScoreInput) -> (ScoreCriterion, Double?, String?, String?) {
        guard input.session.sleepWindow != nil else {
            return (.awakenings, nil, nil, "heure d’endormissement ou de réveil inconnue")
        }
        let count = input.session.significantWakeCount
        return (.awakenings, Self.linear(Double(count), best: 1, worst: 4), count > 1 ? "\(count) réveils" : "\(count) réveil", nil)
    }

    /// Milieu du sommeil, en minutes depuis midi (pour qu'une nuit ne passe pas par zéro).
    func midpoint(of session: SleepSession) -> Double? {
        let times = session.times
        guard let start = times.sleepOnset ?? times.bedtime, let end = times.wake ?? times.getUp, end > start else { return nil }
        let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        let parts = calendar.dateComponents([.hour, .minute], from: middle)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        return (minutes + 12 * 60).truncatingRemainder(dividingBy: 24 * 60)
    }

    private func regularity(_ input: ScoreInput) -> (ScoreCriterion, Double?, String?, String?) {
        guard input.session.kind == .night else {
            return (.regularity, nil, nil, "pas de régularité pour une sieste")
        }
        let reference = input.session.referenceDate
        let previous = input.previousNights
            .filter { $0.kind == .night && $0.referenceDate < reference && $0.id != input.session.id }
            .sorted { $0.referenceDate > $1.referenceDate }
            .prefix(7)
            .compactMap(midpoint(of:))
        guard previous.count >= 3, let tonight = midpoint(of: input.session) else {
            return (.regularity, nil, nil, "il faut au moins 3 nuits précédentes")
        }
        let mean = previous.reduce(0, +) / Double(previous.count)
        let gap = abs(tonight - mean)
        return (.regularity, Self.linear(gap, best: 30, worst: 120), "écart \(format.duration(gap * 60))", nil)
    }

    private func stages(_ input: ScoreInput) -> (ScoreCriterion, Double?, String?, String?) {
        guard let stages = input.stages, stages.measuredNights >= 10 else {
            return (.stages, nil, nil, "phases mesurées par une montre sur au moins 10 nuits")
        }
        let gap = (stages.deepAndREM - stages.personalMedian) * 100
        return (.stages, Self.linear(gap, best: -5, worst: -20), "profond et paradoxal \(Int((stages.deepAndREM * 100).rounded())) %", nil)
    }

    /// Écart en minutes entre une heure et une cible, sur le cadran de 24 heures.
    func deviation(_ date: Date, from target: ClockTime) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        let goal = Double(target.hour * 60 + target.minute)
        let raw = abs(minutes - goal)
        return min(raw, 24 * 60 - raw)
    }

    private func goals(_ input: ScoreInput) -> (ScoreCriterion, Double?, String?, String?) {
        guard input.session.kind == .night else {
            return (.goals, nil, nil, "pas d’objectif pour une sieste")
        }
        let times = input.session.times
        var gaps: [Double] = []
        if let target = input.goals.bedtime, let bedtime = times.bedtime {
            gaps.append(deviation(bedtime, from: target))
        }
        if let target = input.goals.getUp, let getUp = times.getUp ?? times.wake {
            gaps.append(deviation(getUp, from: target))
        }
        guard !gaps.isEmpty else {
            return (.goals, nil, nil, "aucune heure cible choisie")
        }
        let note = gaps.map { Self.linear($0, best: 30, worst: 90) }.reduce(0, +) / Double(gaps.count)
        let worst = gaps.max() ?? 0
        return (.goals, note, "écart \(format.duration(worst * 60))", nil)
    }
}
