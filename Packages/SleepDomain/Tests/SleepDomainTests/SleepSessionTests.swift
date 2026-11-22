import Foundation
import Testing
@testable import SleepDomain

private func time(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 11
    components.day = 21 + dayOffset
    components.hour = hour
    components.minute = minute
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar.date(from: components)!
}

@Suite("Session de sommeil")
struct SleepSessionTests {
    @Test("La correction l'emporte, la détection reste intacte")
    func correctionKeepsDetection() {
        let detected = SessionTimes(bedtime: time(23, 22), sleepOnset: time(23, 41), wake: time(6, 52, dayOffset: 1), getUp: time(6, 57, dayOffset: 1))
        var session = SleepSession(detected: detected)
        session.corrected = SessionTimes(sleepOnset: time(23, 30))

        #expect(session.times.sleepOnset == time(23, 30))
        #expect(session.times.bedtime == time(23, 22))
        #expect(session.detected.sleepOnset == time(23, 41))
    }

    @Test("Durées calculées à partir des horaires retenus")
    func durations() throws {
        let session = SleepSession(detected: SessionTimes(bedtime: time(0, 47), sleepOnset: time(1, 5), wake: time(9, 12), getUp: time(9, 20)))

        #expect(try #require(session.timeInBed) == 8 * 3600 + 33 * 60)
        #expect(try #require(session.sleepLatency) == 18 * 60)
        #expect(try #require(session.sleepWindow) == 8 * 3600 + 7 * 60)
        #expect(session.issues.isEmpty)
    }

    @Test("Horaires dans le désordre signalés")
    func outOfOrder() {
        let session = SleepSession(detected: SessionTimes(bedtime: time(23, 0), sleepOnset: time(22, 30)))

        #expect(session.issues.contains(.timesOutOfOrder))
        #expect(session.sleepLatency == nil)
    }

    @Test("Session de plus de 24 h signalée")
    func tooLong() {
        let session = SleepSession(detected: SessionTimes(bedtime: time(22, 0), getUp: time(23, 0, dayOffset: 1)))

        #expect(session.issues.contains(.longerThanADay))
    }

    @Test("Ressenti borné entre 1 et 5")
    func feelingIsClamped() {
        let feeling = WakeFeeling(mood: 9, energy: 0)

        #expect(feeling.mood == 5)
        #expect(feeling.energy == 1)
    }

    @Test("Dépôt factice : tri, filtre et suppression")
    func inMemoryRepository() async throws {
        let older = SleepSession(detected: SessionTimes(bedtime: time(23, 0)))
        let newer = SleepSession(detected: SessionTimes(bedtime: time(23, 0, dayOffset: 1)))
        let repository = InMemorySleepSessionRepository([older, newer])

        let all = try await repository.sessions(in: nil)
        #expect(all.map(\.id) == [newer.id, older.id])

        let firstDay = DateInterval(start: time(12, 0), end: time(12, 0, dayOffset: 1))
        let filtered = try await repository.sessions(in: firstDay)
        #expect(filtered.map(\.id) == [older.id])

        try await repository.delete(id: older.id)
        #expect(try await repository.session(id: older.id) == nil)
    }
}
