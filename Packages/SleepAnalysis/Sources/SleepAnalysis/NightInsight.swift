import Foundation
import SleepDomain

/// Phrases de l'accueil (maquette E10) : chacune cite ses données.
public enum NightInsight {
    /// Points perdus à partir desquels un critère mérite d'être signalé.
    public static let notableLoss = 5.0

    /// Ce qui fait le plus baisser le score : « Coucher 1 h 47 plus tard que ta moyenne : la régularité fait baisser le score. »
    public static func scoreLine(report: NightReport, session: SleepSession, goals: ScoreGoals = ScoreGoals(), format: SleepFormat) -> String? {
        guard report.score.total != nil else { return nil }
        let losses = report.score.criteria
            .filter(\.isCounted)
            .map { (criterion: $0.criterion, lost: $0.maxPoints - $0.points) }
        guard let worst = losses.max(by: { $0.lost < $1.lost }), worst.lost >= notableLoss else { return nil }
        switch worst.criterion {
        case .regularity:
            if let shift = report.comparison.bedtime, abs(shift) >= 15 * 60 {
                return "Coucher \(format.duration(abs(shift))) plus \(shift > 0 ? "tard" : "tôt") que ta moyenne : la régularité fait baisser le score."
            }
            return "Horaires décalés par rapport à tes nuits précédentes : la régularité fait baisser le score."
        case .duration:
            guard let asleep = session.asleepDuration else { return nil }
            if asleep < goals.duration.lowerBound {
                return "\(format.duration(asleep)) de sommeil, sous ton objectif de \(format.duration(goals.duration.lowerBound)) : la durée fait baisser le score."
            }
            return "\(format.duration(asleep)) de sommeil, au-delà de \(format.duration(goals.duration.upperBound)) : la durée fait baisser le score."
        case .continuity:
            if let latency = session.sleepLatency, latency > 30 * 60 {
                return "Endormissement en \(format.duration(latency)) : la continuité fait baisser le score."
            }
            if session.wakeDuration > 20 * 60 {
                return "\(format.duration(session.wakeDuration)) d’éveil dans la nuit : la continuité fait baisser le score."
            }
            if let efficiency = session.efficiency {
                return "Efficacité de \(Int((efficiency * 100).rounded())) % : la continuité fait baisser le score."
            }
            return nil
        case .awakenings:
            return "\(session.significantWakeCount) réveils de plus de 5 min : ils font baisser le score."
        case .goals:
            return "Horaires loin de tes objectifs : ils font baisser le score."
        case .stages:
            return "Moins de sommeil profond et paradoxal que d’habitude : les phases font baisser le score."
        }
    }

    /// « Dernière nuit : 40 min de plus que ta moyenne, mais un coucher 1 h 47 plus tard. »
    public static func comparisonLine(_ comparison: NightComparison, format: SleepFormat) -> String? {
        guard comparison.referenceNights > 0, let asleep = comparison.asleep else { return nil }
        let durationPart: String
        if abs(asleep) >= 10 * 60 {
            durationPart = "\(format.duration(abs(asleep))) de \(asleep > 0 ? "plus" : "moins") que ta moyenne"
        } else {
            durationPart = "une durée dans ta moyenne"
        }
        guard let shift = comparison.bedtime, abs(shift) >= 30 * 60 else {
            return "Dernière nuit : \(durationPart)."
        }
        let shorter = asleep <= -10 * 60
        let later = shift > 0
        // « mais » quand les deux nouvelles vont en sens contraire (plus de sommeil, coucher plus tard).
        let connector = later != shorter ? "mais" : "et"
        return "Dernière nuit : \(durationPart), \(connector) un coucher \(format.duration(abs(shift))) plus \(later ? "tard" : "tôt")."
    }
}
