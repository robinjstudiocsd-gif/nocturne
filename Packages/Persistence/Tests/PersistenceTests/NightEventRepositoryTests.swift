import Foundation
import SleepDomain
import Testing
@testable import Persistence

@MainActor
@Suite("Base · événements de la nuit")
struct NightEventRepositoryTests {
    @Test("Événements triés par heure, correction gardée, suppression par nuit")
    func events() async throws {
        let repository = SwiftDataNightEventRepository(container: try PersistenceStack.makeContainer(inMemory: true))
        let night = UUID()
        let other = UUID()
        let start = Date(timeIntervalSince1970: 1_795_300_000)
        let snore = NightEvent(sessionID: night, kind: .snoring, start: start.addingTimeInterval(600), duration: 130, confidence: 0.92, intensity: 14)
        let speech = NightEvent(sessionID: night, kind: .speech, start: start.addingTimeInterval(60), duration: 6, confidence: 0.6, intensity: 9, clipPath: "Recordings/x/extrait-001.m4a")
        try await repository.save([snore, speech, NightEvent(sessionID: other, kind: .cough, start: start, duration: 2, confidence: 0.8, intensity: 11)])

        #expect(try await repository.events(sessionID: night).map(\.kind) == [.speech, .snoring])

        let corrected = snore.reclassified(as: .breathing)
        try await repository.save([corrected])
        let reread = try await repository.events(sessionID: night)
        #expect(reread.last?.kind == .breathing)
        #expect(reread.last?.detectedKind == .snoring)
        #expect(reread.last?.origin == .reclassified)
        #expect(reread.first?.clipPath == "Recordings/x/extrait-001.m4a")

        let window = DateInterval(start: start.addingTimeInterval(30), end: start.addingTimeInterval(700))
        #expect(try await repository.events(in: window).count == 2)

        try await repository.delete(id: speech.id)
        #expect(try await repository.events(sessionID: night).count == 1)
        try await repository.deleteAll(sessionID: night)
        #expect(try await repository.events(sessionID: night).isEmpty)
        #expect(try await repository.events(sessionID: other).count == 1)
    }
}
