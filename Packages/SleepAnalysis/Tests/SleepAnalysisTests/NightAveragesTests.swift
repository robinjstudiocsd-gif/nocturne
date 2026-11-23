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

private func night(bed: Date, onset: Date, wake: Date, getUp: Date, wakes: [WakeEpisode] = []) -> SleepSession {
    SleepSession(state: .finished, detected: SessionTimes(bedtime: bed, sleepOnset: onset, wake: wake, getUp: getUp), wakeEpisodes: wakes)
}

/// Trois nuits : 7 h 40, 7 h 20 avec un réveil de 10 min, 8 h ; plus une sieste et une nuit en cours, ignorées.
private func previousNights() -> [SleepSession] {
    [
        night(bed: at(18, 23, 0), onset: at(18, 23, 20), wake: at(19, 7, 0), getUp: at(19, 7, 10)),
        night(bed: at(19, 23, 30), onset: at(19, 23, 45), wake: at(20, 7, 15), getUp: at(20, 7, 20),
              wakes: [WakeEpisode(start: at(20, 3, 0), end: at(20, 3, 10))]),
        night(bed: at(20, 22, 30), onset: at(20, 22, 40), wake: at(21, 6, 40), getUp: at(21, 6, 50)),
        SleepSession(kind: .nap, state: .finished, detected: SessionTimes(bedtime: at(21, 14, 0), sleepOnset: at(21, 14, 5), wake: at(21, 14, 30), getUp: at(21, 14, 30))),
        SleepSession(state: .running, detected: SessionTimes(bedtime: at(22, 23, 0)))
    ]
}

@Suite("Moyennes et comparaison des nuits")
struct NightAveragesTests {
    @Test("Durée, endormissement, réveils, heures moyennes et régularité")
    func averages() {
        let averages = NightAverages(sessions: previousNights(), calendar: paris)

        #expect(averages.nights == 3)
        #expect(averages.asleep == 460 * 60)
        #expect(averages.latency == 15 * 60)
        #expect(abs((averages.wakeCount ?? 0) - 1.0 / 3.0) < 0.0001)
        #expect(averages.bedtime == ClockTime(hour: 23, minute: 0))
        #expect(averages.wake == ClockTime(hour: 6, minute: 58))
        // Milieux du sommeil : 03:10, 03:30 et 02:40 ; écart moyen à leur moyenne : 17 min 47 s.
        #expect(abs((averages.regularity ?? 0) - 1_066.67) < 1)
        #expect(NightAverages(sessions: Array(previousNights().prefix(2)), calendar: paris).regularity == nil)
    }

    @Test("Une nuit comparée aux précédentes : plus courte, coucher plus tard")
    func comparison() {
        let averages = NightAverages(sessions: previousNights(), calendar: paris)
        let tonight = night(bed: at(22, 0, 30), onset: at(22, 0, 45), wake: at(22, 7, 30), getUp: at(22, 7, 40))
        let comparison = NightComparison(session: tonight, previous: averages, calendar: paris)

        #expect(comparison.referenceNights == 3)
        #expect(comparison.asleep == -55 * 60)
        #expect(comparison.bedtime == 90 * 60)
        #expect(abs((comparison.wake ?? 0) - 1_900) < 1)
        #expect(abs((comparison.wakeCount ?? 0) + 1.0 / 3.0) < 0.0001)
    }

    @Test("Heures autour de minuit sans saut")
    func clock() {
        #expect(NightAverages.minutesAfterNoon(at(22, 23, 0), calendar: paris) == 660)
        #expect(NightAverages.minutesAfterNoon(at(22, 0, 30), calendar: paris) == 750)
        #expect(NightAverages.minutesAfterNoon(at(22, 7, 0), calendar: paris) == 1_140)
        #expect(NightAverages.clockTime(750) == ClockTime(hour: 0, minute: 30))
        #expect(NightAverages(sessions: [], calendar: paris).asleep == nil)
    }
}
