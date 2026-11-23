import Foundation
import Testing
@testable import SleepAnalysis
import SleepDomain

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    paris.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

/// Nuit du 21 au 22 : coucher 00:00, endormie 00:15, trois réveils de 10 min, réveil 06:45, lever 07:00.
private func shortNight() -> SleepSession {
    SleepSession(
        state: .finished,
        detected: SessionTimes(bedtime: at(22, 0, 0), sleepOnset: at(22, 0, 15), wake: at(22, 6, 45), getUp: at(22, 7, 0)),
        wakeEpisodes: [2, 3, 4].map { WakeEpisode(start: at(22, $0, 0), end: at(22, $0, 10)) }
    )
}

/// Nuits précédentes : coucher 23:30, lever 07:30, milieu à 03:30.
private func previousNights() -> [SleepSession] {
    [18, 19, 20].map { day in
        SleepSession(state: .finished, detected: SessionTimes(bedtime: at(day, 23, 30), wake: at(day + 1, 7, 30), getUp: at(day + 1, 7, 30)))
    }
}

@Suite("Score de sommeil")
struct ScoreTests {
    private let scorer = SleepScorer(calendar: paris)

    @Test("Notes linéaires entre les bornes")
    func linear() {
        #expect(SleepScorer.linear(0.75, best: 0.85, worst: 0.65) == 0.5)
        #expect(SleepScorer.linear(40, best: 20, worst: 60) == 0.5)
        #expect(SleepScorer.linear(10, best: 20, worst: 60) == 1)
        #expect(SleepScorer.linear(0.6, best: 0.85, worst: 0.65) == 0)
    }

    @Test("Cinq critères comptés : poids redistribués, score arrondi")
    func mixedNight() throws {
        let input = ScoreInput(
            session: shortNight(),
            previousNights: previousNights(),
            timesReliability: .medium,
            goals: ScoreGoals(bedtime: ClockTime(hour: 23, minute: 0), getUp: ClockTime(hour: 7, minute: 0))
        )
        let score = scorer.score(input)

        let notes = Dictionary(uniqueKeysWithValues: score.criteria.map { ($0.criterion, $0.note) })
        #expect(notes[.duration] == 0.5)
        #expect(abs(((notes[.continuity] ?? nil) ?? 0) - 11.0 / 12.0) < 0.0001)
        #expect(abs(((notes[.awakenings] ?? nil) ?? 0) - 1.0 / 3.0) < 0.0001)
        #expect(notes[.regularity] == 1)
        #expect(notes[.goals] == 0.75)
        #expect(notes[.stages] == .some(nil))
        #expect(score.countedWeight == 90)
        #expect(score.total == 71)
        #expect(score.reliability == .medium)
        #expect(score.displayText == "71")
        let duration = try #require(score.criteria.first { $0.criterion == .duration })
        #expect(abs(duration.maxPoints - 100.0 / 3.0) < 0.0001)
        #expect(duration.value == "6 h")
        #expect(score.criteria.first { $0.criterion == .stages }?.missing == "phases mesurées par une montre sur au moins 10 nuits")
        #expect(scorer.quality(of: shortNight()) == .good)
    }

    @Test("Peu de critères : fiabilité baissée, score arrondi à 5 et « environ »")
    func approximate() {
        var night = shortNight()
        night.wakeEpisodes = []
        let score = scorer.score(ScoreInput(session: night, timesReliability: .medium))

        #expect(score.countedWeight == 60)
        #expect(score.reliability == .low)
        #expect(score.isApproximate)
        #expect(score.total.map { $0 % 5 } == 0)
        #expect(score.displayText.hasPrefix("environ "))
    }

    @Test("Score indisponible : données manquantes listées, horaires peu fiables écartés")
    func unavailable() {
        let night = SleepSession(state: .finished, detected: SessionTimes(bedtime: at(21, 23, 0), getUp: at(22, 7, 0)))
        let score = scorer.score(ScoreInput(session: night, previousNights: previousNights()))

        #expect(score.total == nil)
        #expect(score.displayText == "Score indisponible")
        #expect(score.missing.contains("Durée : heure d’endormissement ou de réveil inconnue"))

        let unreliable = scorer.score(ScoreInput(session: shortNight(), previousNights: previousNights(), timesReliability: .low))
        #expect(unreliable.total == nil)
        #expect(unreliable.missing.contains("Durée : horaires trop peu fiables"))
    }

    @Test("Fiabilité des horaires selon leur origine ; une correction vaut une saisie")
    func timesReliability() {
        var night = shortNight()
        night.primarySource = .microphone
        #expect(night.timesReliability == .low)
        #expect(ScoreInput(session: night).timesReliability == .low)

        night.corrected.wake = at(22, 6, 30)
        #expect(night.timesReliability == .medium)

        night.primarySource = .watch
        #expect(night.timesReliability == .high)

        night.primarySource = .motion
        night.corrected = SessionTimes()
        #expect(night.timesReliability == .medium)
    }

    @Test("Régularité : il faut 3 nuits précédentes ; écart aux cibles sur le cadran")
    func regularityAndGoals() {
        let two = scorer.score(ScoreInput(session: shortNight(), previousNights: Array(previousNights().prefix(2))))
        #expect(two.criteria.first { $0.criterion == .regularity }?.note == nil)
        #expect(scorer.deviation(at(22, 0, 10), from: ClockTime(hour: 23, minute: 30)) == 40)
    }
}

@Suite("Dette de sommeil")
struct SleepDebtTests {
    @Test("Écart cumulé sur les jours mesurés ; un jour sans nuit ne compte pas")
    func debt() {
        func night(_ day: Int, hours: Double) -> SleepSession {
            let onset = at(day, 23, 0)
            let wake = onset.addingTimeInterval(hours * 3_600)
            return SleepSession(state: .finished, detected: SessionTimes(bedtime: onset, sleepOnset: onset, wake: wake, getUp: wake))
        }
        let nap = SleepSession(kind: .nap, state: .finished, detected: SessionTimes(bedtime: at(21, 14, 0), sleepOnset: at(21, 14, 0), wake: at(21, 14, 30), getUp: at(21, 14, 30)))
        let sessions = [night(18, hours: 7), night(19, hours: 6), night(20, hours: 8.5), nap]

        let debt = SleepDebt.compute(sessions: sessions, need: 7.5 * 3_600, through: at(22, 9, 0), days: 14, calendar: paris)

        #expect(debt.days.count == 14)
        #expect(debt.days.last?.day == at(22, 0, 0))
        #expect(debt.days.compactMap(\.balance).count == 3)
        // −30 min, −1 h 30, puis +1 h 30 grâce à la sieste du 21 : 30 min de dette.
        #expect(debt.total == 30 * 60)
        #expect(debt.days.first { $0.day == at(21, 0, 0) }?.slept == 8.5 * 3_600 + 1_800)
    }
}
