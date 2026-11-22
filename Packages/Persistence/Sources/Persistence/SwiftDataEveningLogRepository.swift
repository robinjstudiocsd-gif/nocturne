import Foundation
import SleepDomain
import SwiftData

/// Dépôt des journaux du soir sur SwiftData : un seul journal par jour.
@MainActor
public final class SwiftDataEveningLogRepository: EveningLogRepository {
    private let container: ModelContainer
    private let context: ModelContext
    private let calendar: Calendar

    public init(container: ModelContainer, calendar: Calendar = .current) {
        self.container = container
        self.context = container.mainContext
        self.calendar = calendar
    }

    public func log(forDay day: Date) async throws -> EveningLog? {
        let start = calendar.startOfDay(for: day)
        var descriptor = FetchDescriptor<EveningLogRecord>(predicate: #Predicate<EveningLogRecord> { $0.day == start })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.log
    }

    public func logs(in interval: DateInterval?) async throws -> [EveningLog] {
        let start = interval?.start ?? .distantPast
        let end = interval?.end ?? .distantFuture
        let descriptor = FetchDescriptor<EveningLogRecord>(
            predicate: #Predicate<EveningLogRecord> { $0.day >= start && $0.day <= end },
            sortBy: [SortDescriptor(\.day, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.log)
    }

    public func save(_ log: EveningLog) async throws {
        let day = log.day
        let sameDay = try context.fetch(FetchDescriptor<EveningLogRecord>(predicate: #Predicate<EveningLogRecord> { $0.day == day }))
        var updated = false
        for record in sameDay {
            if record.id == log.id {
                record.apply(log)
                updated = true
            } else {
                context.delete(record)
            }
        }
        if !updated {
            context.insert(EveningLogRecord(log: log))
        }
        try context.save()
    }

    public func delete(id: UUID) async throws {
        let matches = try context.fetch(FetchDescriptor<EveningLogRecord>(predicate: #Predicate<EveningLogRecord> { $0.id == id }))
        guard !matches.isEmpty else { return }
        matches.forEach { context.delete($0) }
        try context.save()
    }
}
