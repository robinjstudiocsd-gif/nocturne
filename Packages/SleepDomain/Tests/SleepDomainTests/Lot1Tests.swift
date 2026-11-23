import Foundation
import Testing
@testable import SleepDomain

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    paris.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

/// Horloge de test qu'on fait avancer à la main.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func set(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }
}

@Suite("Lot 1 · Nuits")
struct Lot1Tests {
    @Test("Démarrer puis arrêter une nuit sans audio")
    func startAndStop() async throws {
        let clock = TestClock(date(22, 23, 22))
        let repository = InMemorySleepSessionRepository()
        let lifecycle = SessionLifecycle(repository: repository, now: { clock.now })

        let started = try await lifecycle.start(kind: .night, mode: .continuous)
        #expect(started.state == .running)
        #expect(started.detected.bedtime == date(22, 23, 22))

        let again = try await lifecycle.start(kind: .nap, mode: .off)
        #expect(again.id == started.id)

        clock.set(date(23, 6, 52))
        let stopped = try await lifecycle.stop(id: started.id)
        #expect(stopped.state == .finished)
        #expect(stopped.detected.wake == date(23, 6, 52))
        #expect(try await lifecycle.running() == nil)
    }

    @Test("L'analyse de la nuit remplace la détection, garde les réveils saisis et le lever")
    func saveDetection() async throws {
        let clock = TestClock(date(22, 23, 0))
        let repository = InMemorySleepSessionRepository()
        let lifecycle = SessionLifecycle(repository: repository, now: { clock.now })
        let session = try await lifecycle.start(kind: .night, mode: .continuous)
        clock.set(date(23, 7, 0))
        try await lifecycle.stop(id: session.id)
        let typed = WakeEpisode(start: date(23, 4, 0), end: date(23, 4, 20))
        try await lifecycle.applyCorrection(id: session.id, corrected: SessionTimes(), wakeEpisodes: [typed], kind: .night, comment: nil)

        let detected = WakeEpisode(start: date(23, 2, 0), end: date(23, 2, 10), source: .motion)
        let saved = try await lifecycle.saveDetection(
            id: session.id,
            sleepOnset: date(22, 23, 25),
            wake: date(23, 6, 40),
            wakeEpisodes: [detected],
            source: .motion,
            analysisVersion: 1
        )
        #expect(saved.detected.bedtime == date(22, 23, 0))
        #expect(saved.detected.sleepOnset == date(22, 23, 25))
        #expect(saved.detected.wake == date(23, 6, 40))
        #expect(saved.detected.getUp == date(23, 7, 0))
        #expect(saved.wakeEpisodes.map(\.start) == [date(23, 2, 0), date(23, 4, 0)])
        #expect(saved.primarySource == .motion)
        #expect(saved.analysisVersion == 1)

        let again = try await lifecycle.saveDetection(id: session.id, sleepOnset: nil, wake: nil, wakeEpisodes: [], source: nil, analysisVersion: 1)
        #expect(again.wakeEpisodes == [typed])
        #expect(again.detected.sleepOnset == date(22, 23, 25))
    }

    @Test("Une nuit interrompue se termine à la dernière minute connue")
    func closeInterrupted() async throws {
        let lifecycle = SessionLifecycle(repository: InMemorySleepSessionRepository(), now: { date(22, 23, 0) })
        let session = try await lifecycle.start(kind: .night, mode: .continuous)

        let closed = try await lifecycle.close(id: session.id, at: date(23, 2, 14))
        #expect(closed.state == .interrupted)
        #expect(closed.detected.wake == date(23, 2, 14))
        #expect(try await lifecycle.running() == nil)
    }

    @Test("Arrêter une session déjà terminée est refusé")
    func stopTwice() async throws {
        let lifecycle = SessionLifecycle(repository: InMemorySleepSessionRepository(), now: { date(22, 23, 0) })
        let session = try await lifecycle.start(kind: .night, mode: .continuous)
        try await lifecycle.stop(id: session.id)

        await #expect(throws: SessionError.notRunning) {
            try await lifecycle.stop(id: session.id)
        }
    }

    @Test("Saisie manuelle : horaires dans le désordre refusés")
    func manualEntryValidation() async throws {
        let lifecycle = SessionLifecycle(repository: InMemorySleepSessionRepository())
        let wrong = SessionTimes(bedtime: date(20, 23, 30), sleepOnset: date(20, 23, 10))

        await #expect(throws: SessionError.invalidTimes([.timesOutOfOrder])) {
            try await lifecycle.addManual(kind: .night, times: wrong, comment: nil)
        }

        let right = SessionTimes(bedtime: date(20, 23, 30), sleepOnset: date(20, 23, 50), wake: date(21, 7, 5), getUp: date(21, 7, 15))
        let saved = try await lifecycle.addManual(kind: .night, times: right, comment: "  ")
        #expect(saved.state == .manual)
        #expect(saved.comment == nil)
        let expectedWindow: TimeInterval = (7 * 60 + 15) * 60
        #expect(saved.sleepWindow == expectedWindow)
    }

    @Test("Correction : la détection reste, les réveils sont triés et comptés")
    func correction() async throws {
        let repository = InMemorySleepSessionRepository()
        let lifecycle = SessionLifecycle(repository: repository)
        let detected = SessionTimes(bedtime: date(22, 0, 47), sleepOnset: date(22, 1, 5), wake: date(22, 9, 12), getUp: date(22, 9, 20))
        let session = SleepSession(state: .finished, detected: detected)
        try await repository.save(session)

        let episodes = [
            WakeEpisode(start: date(22, 4, 46), end: date(22, 4, 53)),
            WakeEpisode(start: date(22, 3, 37), end: date(22, 3, 42))
        ]
        let corrected = try await lifecycle.applyCorrection(
            id: session.id,
            corrected: SessionTimes(sleepOnset: date(22, 0, 58)),
            wakeEpisodes: episodes,
            kind: .night,
            comment: "Soirée chez des amis"
        )

        #expect(corrected.detected.sleepOnset == date(22, 1, 5))
        #expect(corrected.times.sleepOnset == date(22, 0, 58))
        #expect(corrected.wakeEpisodes.first?.start == date(22, 3, 37))
        #expect(corrected.significantWakeCount == 1)
        let expectedWake: TimeInterval = 12 * 60
        #expect(corrected.wakeDuration == expectedWake)
        let expectedAsleep: TimeInterval = (8 * 60 + 14 - 12) * 60
        #expect(corrected.asleepDuration == expectedAsleep)
    }

    @Test("Une nuit commencée après minuit appartient à la veille")
    func nightTitle() {
        let nights = NightCalendar(calendar: paris)
        let session = SleepSession(detected: SessionTimes(bedtime: date(22, 0, 47)))

        #expect(nights.evening(of: session) == paris.startOfDay(for: date(21, 12, 0)))
        #expect(nights.title(of: session) == "Nuit du samedi 21 au dimanche 22 novembre")

        let nap = SleepSession(kind: .nap, detected: SessionTimes(bedtime: date(20, 14, 10)))
        #expect(nights.title(of: nap) == "Sieste du vendredi 20 novembre")
    }

    @Test("Journal du soir : un seul par jour, stress borné")
    func eveningLog() async throws {
        let repository = InMemoryEveningLogRepository(calendar: paris)
        var first = EveningLog(day: date(22, 22, 40), caffeine: .one, stress: 9, calendar: paris)
        #expect(first.stress == 5)
        #expect(!first.isEmpty)
        try await repository.save(first)

        first.stress = 0
        #expect(first.stress == 1)

        let replacement = EveningLog(day: date(22, 8, 0), meal: .light, calendar: paris)
        try await repository.save(replacement)

        let stored = try await repository.log(forDay: date(22, 12, 0))
        #expect(stored?.id == replacement.id)
        #expect(try await repository.logs(in: nil).count == 1)
        #expect(EveningLog(day: date(22, 20, 0), note: "   ", calendar: paris).isEmpty)
    }
}
