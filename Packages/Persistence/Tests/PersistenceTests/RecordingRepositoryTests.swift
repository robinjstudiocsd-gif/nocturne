import Foundation
import SleepDomain
import Testing
@testable import Persistence

@MainActor
@Suite("Base · tranches et trous")
struct RecordingRepositoryTests {
    @Test("Tranches triées par rang, trous par heure, suppression d'une nuit")
    func segmentsAndGaps() async throws {
        let repository = SwiftDataRecordingRepository(container: try PersistenceStack.makeContainer(inMemory: true))
        let night = UUID()
        let other = UUID()
        let start = Date(timeIntervalSince1970: 1_795_300_000)

        var second = AudioSegment(sessionID: night, index: 2, start: start.addingTimeInterval(300), duration: 120, relativePath: "Recordings/x/tranche-002.m4a", byteSize: 480_000, quality: .standard, state: .recording)
        let first = AudioSegment(sessionID: night, index: 1, start: start, duration: 300, relativePath: "Recordings/x/tranche-001.m4a", byteSize: 1_200_000, quality: .standard, state: .complete)
        try await repository.save(second)
        try await repository.save(first)
        try await repository.save(AudioSegment(sessionID: other, index: 1, start: start, duration: 300, relativePath: "y", byteSize: 1, quality: .high, state: .complete))

        second.state = .truncated
        try await repository.save(second)

        let segments = try await repository.segments(sessionID: night)
        #expect(segments.map(\.index) == [1, 2])
        #expect(segments.last?.state == .truncated)

        let gap = RecordingGap(sessionID: night, start: start.addingTimeInterval(420), end: start.addingTimeInterval(1_140), cause: .phoneCall)
        let earlier = RecordingGap(sessionID: other, start: start.addingTimeInterval(60), end: start.addingTimeInterval(90), cause: .siri)
        try await repository.save(gap)
        try await repository.save(earlier)
        #expect(try await repository.gaps(sessionID: night) == [gap])
        #expect(try await repository.allGaps() == [earlier, gap])

        try await repository.deleteAll(sessionID: night)
        #expect(try await repository.segments(sessionID: night).isEmpty)
        #expect(try await repository.gaps(sessionID: night).isEmpty)
        #expect(try await repository.segments(sessionID: other).count == 1)
    }
}
