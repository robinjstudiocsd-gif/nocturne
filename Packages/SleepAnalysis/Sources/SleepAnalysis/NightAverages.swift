import Foundation
import SleepDomain

/// Moyennes d'une série de nuits (siestes et nuits en cours exclues) : durée, heures de coucher et de réveil,
/// régularité et réveils (étude : tableau de bord et statistiques).
public struct NightAverages: Equatable, Sendable {
    /// La régularité des horaires n'a de sens qu'à partir de 3 nuits.
    public static let minimumNightsForRegularity = 3

    /// Nuits comptées.
    public var nights: Int
    /// Durée moyenne de sommeil.
    public var asleep: TimeInterval?
    public var timeInBed: TimeInterval?
    /// Délai moyen d'endormissement.
    public var latency: TimeInterval?
    /// Réveils de plus de 5 minutes, en moyenne par nuit.
    public var wakeCount: Double?
    /// Part moyenne du temps au lit passée à dormir.
    public var efficiency: Double?
    /// Heure moyenne de coucher, en minutes après midi (une nuit ne passe pas par zéro).
    public var bedtimeMinutes: Double?
    /// Heure moyenne de réveil (ou de lever s'il manque), en minutes après midi.
    public var wakeMinutes: Double?
    /// Écart moyen du milieu du sommeil à sa moyenne : plus il est petit, plus les horaires sont réguliers.
    public var regularity: TimeInterval?

    public init(sessions: [SleepSession], calendar: Calendar = .current) {
        let nights = sessions.filter { $0.kind == .night && $0.state != .running }
        self.nights = nights.count
        asleep = Self.mean(nights.compactMap(\.asleepDuration))
        timeInBed = Self.mean(nights.compactMap(\.timeInBed))
        latency = Self.mean(nights.compactMap(\.sleepLatency))
        wakeCount = Self.mean(nights.filter { $0.sleepWindow != nil }.map { Double($0.significantWakeCount) })
        efficiency = Self.mean(nights.compactMap(\.efficiency))
        bedtimeMinutes = Self.mean(nights.compactMap { $0.times.bedtime.map { Self.minutesAfterNoon($0, calendar: calendar) } })
        wakeMinutes = Self.mean(nights.compactMap { night in
            (night.times.wake ?? night.times.getUp).map { Self.minutesAfterNoon($0, calendar: calendar) }
        })
        let midpoints = nights.compactMap { Self.midpoint(of: $0, calendar: calendar) }
        if midpoints.count >= Self.minimumNightsForRegularity, let center = Self.mean(midpoints) {
            regularity = (Self.mean(midpoints.map { abs($0 - center) }) ?? 0) * 60
        } else {
            regularity = nil
        }
    }

    /// Heure moyenne de coucher.
    public var bedtime: ClockTime? {
        bedtimeMinutes.map(Self.clockTime)
    }

    /// Heure moyenne de réveil.
    public var wake: ClockTime? {
        wakeMinutes.map(Self.clockTime)
    }

    // MARK: - Calculs

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Minutes écoulées depuis midi : 23:00 donne 660, 07:00 donne 1 140.
    static func minutesAfterNoon(_ date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        return (minutes + 12 * 60).truncatingRemainder(dividingBy: 24 * 60)
    }

    /// Milieu du sommeil (de l'endormissement, ou du coucher, au réveil), en minutes après midi.
    static func midpoint(of session: SleepSession, calendar: Calendar) -> Double? {
        let times = session.times
        guard let start = times.sleepOnset ?? times.bedtime, let end = times.wake ?? times.getUp, end > start else { return nil }
        return minutesAfterNoon(start.addingTimeInterval(end.timeIntervalSince(start) / 2), calendar: calendar)
    }

    static func clockTime(_ minutesAfterNoon: Double) -> ClockTime {
        let total = (Int(minutesAfterNoon.rounded()) + 12 * 60) % (24 * 60)
        return ClockTime(hour: total / 60, minute: total % 60)
    }
}

/// Une nuit comparée à la moyenne des nuits précédentes (étude : « Comparaison avec les nuits précédentes »).
/// Chaque écart est positif quand la nuit est plus longue, plus tardive ou plus agitée que d'habitude.
public struct NightComparison: Equatable, Sendable {
    public var asleep: TimeInterval?
    /// Coucher plus tard (positif) ou plus tôt (négatif) que d'habitude.
    public var bedtime: TimeInterval?
    /// Réveil plus tard (positif) ou plus tôt (négatif) que d'habitude.
    public var wake: TimeInterval?
    public var wakeCount: Double?
    /// Nuits précédentes qui servent de référence.
    public var referenceNights: Int

    public init(session: SleepSession, previous: NightAverages, calendar: Calendar = .current) {
        referenceNights = previous.nights
        asleep = Self.difference(session.asleepDuration, previous.asleep)
        bedtime = Self.difference(
            session.times.bedtime.map { NightAverages.minutesAfterNoon($0, calendar: calendar) },
            previous.bedtimeMinutes
        ).map { $0 * 60 }
        wake = Self.difference(
            (session.times.wake ?? session.times.getUp).map { NightAverages.minutesAfterNoon($0, calendar: calendar) },
            previous.wakeMinutes
        ).map { $0 * 60 }
        wakeCount = session.sleepWindow == nil ? nil : Self.difference(Double(session.significantWakeCount), previous.wakeCount)
    }

    static func difference(_ value: Double?, _ reference: Double?) -> Double? {
        guard let value, let reference else { return nil }
        return value - reference
    }
}
