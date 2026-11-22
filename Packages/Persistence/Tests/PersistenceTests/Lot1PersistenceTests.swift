import Foundation
import SleepDomain
import Testing
@testable import Persistence

@MainActor
@Suite("Base · lot 1")
struct Lot1PersistenceTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test("Les réveils de la nuit sont gardés")
    func wakeEpisodesRoundTrip() async throws {
        let repository = SwiftDataSleepSessionRepository(container: try PersistenceStack.makeContainer(inMemory: true))
        let episode = WakeEpisode(start: date(22, 4, 46), end: date(22, 4, 53), source: .watch)
        let session = SleepSession(state: .finished, detected: SessionTimes(bedtime: date(22, 0, 47)), wakeEpisodes: [episode])

        try await repository.save(session)
        let loaded = try #require(try await repository.session(id: session.id))

        #expect(loaded.wakeEpisodes == [episode])
        #expect(loaded.significantWakeCount == 1)
    }

    @Test("Un journal du soir par jour, relu par sa date")
    func eveningLogs() async throws {
        let repository = SwiftDataEveningLogRepository(container: try PersistenceStack.makeContainer(inMemory: true), calendar: calendar)
        let first = EveningLog(day: date(22, 22, 40), caffeine: .one, lastCaffeine: date(22, 16, 0), stress: 2, meal: .normal, mealEnd: date(22, 20, 30), calendar: calendar)
        try await repository.save(first)

        let loaded = try #require(try await repository.log(forDay: date(22, 9, 0)))
        #expect(loaded.caffeine == .one)
        #expect(loaded.lastCaffeine == date(22, 16, 0))
        #expect(loaded.stress == 2)

        var edited = loaded
        edited.exercise = .light
        try await repository.save(edited)

        let replacement = EveningLog(day: date(22, 23, 0), note: "Nouvelle saisie", calendar: calendar)
        try await repository.save(replacement)

        let all = try await repository.logs(in: nil)
        #expect(all.count == 1)
        #expect(all.first?.id == replacement.id)

        try await repository.delete(id: replacement.id)
        #expect(try await repository.logs(in: nil).isEmpty)
    }
}
