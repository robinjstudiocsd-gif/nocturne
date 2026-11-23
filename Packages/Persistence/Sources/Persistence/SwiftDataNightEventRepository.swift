import Foundation
import SleepDomain
import SwiftData

/// Dépôt des événements de la nuit sur SwiftData.
@MainActor
public final class SwiftDataNightEventRepository: NightEventRepository {
    private let container: ModelContainer
    private let context: ModelContext

    public init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    public func events(sessionID: UUID) async throws -> [NightEvent] {
        let descriptor = FetchDescriptor<NightEventRecord>(
            predicate: #Predicate<NightEventRecord> { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.start)]
        )
        return try context.fetch(descriptor).map(\.event)
    }

    public func events(in interval: DateInterval?) async throws -> [NightEvent] {
        var descriptor = FetchDescriptor<NightEventRecord>(sortBy: [SortDescriptor(\.start)])
        if let interval {
            let start = interval.start
            let end = interval.end
            descriptor.predicate = #Predicate<NightEventRecord> { $0.start >= start && $0.start <= end }
        }
        return try context.fetch(descriptor).map(\.event)
    }

    public func save(_ events: [NightEvent]) async throws {
        for event in events {
            let id = event.id
            var descriptor = FetchDescriptor<NightEventRecord>(predicate: #Predicate<NightEventRecord> { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.apply(event)
            } else {
                context.insert(NightEventRecord(event: event))
            }
        }
        try context.save()
    }

    public func delete(id: UUID) async throws {
        try context.delete(model: NightEventRecord.self, where: #Predicate<NightEventRecord> { $0.id == id })
        try context.save()
    }

    public func deleteAll(sessionID: UUID) async throws {
        try context.delete(model: NightEventRecord.self, where: #Predicate<NightEventRecord> { $0.sessionID == sessionID })
        try context.save()
    }
}
