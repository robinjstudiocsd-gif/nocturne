import Foundation
import SleepDomain
import Testing
@testable import Persistence

@MainActor
@Suite("Base des sessions")
struct SleepSessionRepositoryTests {
    private func makeRepository() throws -> SwiftDataSleepSessionRepository {
        SwiftDataSleepSessionRepository(container: try PersistenceStack.makeContainer(inMemory: true))
    }

    @Test("Enregistrer puis relire une session complète")
    func roundTrip() async throws {
        let repository = try makeRepository()
        let bedtime = Date(timeIntervalSince1970: 1_795_300_000)
        var session = SleepSession(
            kind: .night,
            state: .finished,
            detected: SessionTimes(bedtime: bedtime, sleepOnset: bedtime.addingTimeInterval(1_080), wake: bedtime.addingTimeInterval(29_100), getUp: bedtime.addingTimeInterval(29_580)),
            primarySource: .microphone,
            recordingMode: .continuous,
            analysisVersion: 1,
            comment: "Soirée chez des amis",
            feeling: WakeFeeling(mood: 4, energy: 3)
        )
        session.corrected.sleepOnset = bedtime.addingTimeInterval(900)

        try await repository.save(session)
        let loaded = try #require(try await repository.session(id: session.id))

        #expect(loaded == session)
        #expect(loaded.detected.sleepOnset == bedtime.addingTimeInterval(1_080))
        #expect(loaded.times.sleepOnset == bedtime.addingTimeInterval(900))
    }

    @Test("Modifier une session existante ne crée pas de doublon")
    func updateInPlace() async throws {
        let repository = try makeRepository()
        var session = SleepSession(detected: SessionTimes(bedtime: Date(timeIntervalSince1970: 1_795_300_000)))
        try await repository.save(session)

        session.comment = "Réveillé par un scooter"
        session.state = .finished
        try await repository.save(session)

        let all = try await repository.sessions(in: nil)
        #expect(all.count == 1)
        #expect(all.first?.comment == "Réveillé par un scooter")
        #expect(all.first?.state == .finished)
    }

    @Test("Tri de la plus récente à la plus ancienne, filtre par période et suppression")
    func sortFilterDelete() async throws {
        let repository = try makeRepository()
        let base = Date(timeIntervalSince1970: 1_795_300_000)
        let older = SleepSession(detected: SessionTimes(bedtime: base))
        let newer = SleepSession(detected: SessionTimes(bedtime: base.addingTimeInterval(86_400)))
        try await repository.save(older)
        try await repository.save(newer)

        #expect(try await repository.sessions(in: nil).map(\.id) == [newer.id, older.id])

        let firstDay = DateInterval(start: base.addingTimeInterval(-3_600), duration: 7_200)
        #expect(try await repository.sessions(in: firstDay).map(\.id) == [older.id])

        try await repository.delete(id: older.id)
        #expect(try await repository.session(id: older.id) == nil)
        #expect(try await repository.sessions(in: nil).count == 1)
    }

    @Test("Le journal garde les lignes dans l'ordre")
    func journal() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let journal = FileDiagnosticJournal(fileURL: url)

        journal.record("Première ligne")
        try await Task.sleep(for: .milliseconds(200))
        journal.record("Deuxième ligne")
        try await Task.sleep(for: .milliseconds(200))

        let lines = await journal.recentLines(limit: 10)
        #expect(lines.count == 2)
        #expect(lines.first?.hasSuffix("Première ligne") == true)
        #expect(lines.last?.hasSuffix("Deuxième ligne") == true)
    }
}
