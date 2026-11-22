import Foundation
import SleepDomain
import SwiftData

/// Dépôt des sessions sur SwiftData. Il tourne sur le fil principal, comme le contexte de la base.
@MainActor
public final class SwiftDataSleepSessionRepository: SleepSessionRepository {
    /// Le contexte ne retient pas la base : le dépôt la garde en vie lui-même.
    private let container: ModelContainer
    private let context: ModelContext

    public init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    public func sessions(in interval: DateInterval?) async throws -> [SleepSession] {
        let start = interval?.start ?? .distantPast
        let end = interval?.end ?? .distantFuture
        let descriptor = FetchDescriptor<SleepSessionRecord>(
            predicate: #Predicate<SleepSessionRecord> { $0.referenceDate >= start && $0.referenceDate <= end },
            sortBy: [SortDescriptor(\.referenceDate, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.session)
    }

    public func session(id: UUID) async throws -> SleepSession? {
        try record(id: id)?.session
    }

    public func save(_ session: SleepSession) async throws {
        if let existing = try record(id: session.id) {
            existing.apply(session)
        } else {
            context.insert(SleepSessionRecord(session: session))
        }
        try context.save()
    }

    public func delete(id: UUID) async throws {
        guard let existing = try record(id: id) else { return }
        context.delete(existing)
        try context.save()
    }

    private func record(id: UUID) throws -> SleepSessionRecord? {
        var descriptor = FetchDescriptor<SleepSessionRecord>(predicate: #Predicate<SleepSessionRecord> { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
