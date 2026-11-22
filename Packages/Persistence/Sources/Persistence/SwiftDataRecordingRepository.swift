import Foundation
import SleepDomain
import SwiftData

/// Dépôt des tranches audio et des trous d'enregistrement sur SwiftData.
@MainActor
public final class SwiftDataRecordingRepository: RecordingRepository {
    private let container: ModelContainer
    private let context: ModelContext

    public init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    public func segments(sessionID: UUID) async throws -> [AudioSegment] {
        let descriptor = FetchDescriptor<AudioSegmentRecord>(
            predicate: #Predicate<AudioSegmentRecord> { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.index)]
        )
        return try context.fetch(descriptor).map(\.segment)
    }

    public func save(_ segment: AudioSegment) async throws {
        let id = segment.id
        var descriptor = FetchDescriptor<AudioSegmentRecord>(predicate: #Predicate<AudioSegmentRecord> { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.apply(segment)
        } else {
            context.insert(AudioSegmentRecord(segment: segment))
        }
        try context.save()
    }

    public func gaps(sessionID: UUID) async throws -> [RecordingGap] {
        let descriptor = FetchDescriptor<RecordingGapRecord>(
            predicate: #Predicate<RecordingGapRecord> { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.start)]
        )
        return try context.fetch(descriptor).map(\.gap)
    }

    public func save(_ gap: RecordingGap) async throws {
        let id = gap.id
        var descriptor = FetchDescriptor<RecordingGapRecord>(predicate: #Predicate<RecordingGapRecord> { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.apply(gap)
        } else {
            context.insert(RecordingGapRecord(gap: gap))
        }
        try context.save()
    }

    public func deleteAll(sessionID: UUID) async throws {
        try context.delete(model: AudioSegmentRecord.self, where: #Predicate<AudioSegmentRecord> { $0.sessionID == sessionID })
        try context.delete(model: RecordingGapRecord.self, where: #Predicate<RecordingGapRecord> { $0.sessionID == sessionID })
        try context.save()
    }
}
