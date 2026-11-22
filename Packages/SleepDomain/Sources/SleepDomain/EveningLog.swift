import Foundation

/// Journal du soir : ce qui peut influencer la nuit qui suit.
public struct EveningLog: Identifiable, Hashable, Codable, Sendable {
    public enum Caffeine: String, Codable, Sendable, CaseIterable {
        case none
        case one
        case two
        case threeOrMore
    }

    public enum Exercise: String, Codable, Sendable, CaseIterable {
        case none
        case light
        case intense
    }

    public enum Screens: String, Codable, Sendable, CaseIterable {
        case offEarly
        case untilBedtime
        case inBed
    }

    public enum Meal: String, Codable, Sendable, CaseIterable {
        case light
        case normal
        case heavy
    }

    public var id: UUID
    /// Le soir concerné, ramené au début de la journée.
    public var day: Date
    public var caffeine: Caffeine?
    public var lastCaffeine: Date?
    public var exercise: Exercise?
    public var exerciseEnd: Date?
    public var screens: Screens?
    /// Stress de la journée, de 1 (calme) à 5 (très tendu).
    public var stress: Int? {
        didSet { stress = stress.map { min(5, max(1, $0)) } }
    }
    public var meal: Meal?
    public var mealEnd: Date?
    public var note: String?

    public init(
        id: UUID = UUID(),
        day: Date,
        caffeine: Caffeine? = nil,
        lastCaffeine: Date? = nil,
        exercise: Exercise? = nil,
        exerciseEnd: Date? = nil,
        screens: Screens? = nil,
        stress: Int? = nil,
        meal: Meal? = nil,
        mealEnd: Date? = nil,
        note: String? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.day = calendar.startOfDay(for: day)
        self.caffeine = caffeine
        self.lastCaffeine = lastCaffeine
        self.exercise = exercise
        self.exerciseEnd = exerciseEnd
        self.screens = screens
        self.stress = stress.map { min(5, max(1, $0)) }
        self.meal = meal
        self.mealEnd = mealEnd
        self.note = note
    }

    /// Vrai si rien n'a été renseigné.
    public var isEmpty: Bool {
        caffeine == nil && exercise == nil && screens == nil && stress == nil && meal == nil
            && (note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

/// Accès aux journaux du soir.
public protocol EveningLogRepository: Sendable {
    func log(forDay day: Date) async throws -> EveningLog?
    func logs(in interval: DateInterval?) async throws -> [EveningLog]
    func save(_ log: EveningLog) async throws
    func delete(id: UUID) async throws
}

/// Version factice, pour les tests et les aperçus.
public actor InMemoryEveningLogRepository: EveningLogRepository {
    private var storage: [UUID: EveningLog] = [:]
    private let calendar: Calendar

    public init(_ logs: [EveningLog] = [], calendar: Calendar = .current) {
        self.calendar = calendar
        for log in logs {
            storage[log.id] = log
        }
    }

    public func log(forDay day: Date) async throws -> EveningLog? {
        let start = calendar.startOfDay(for: day)
        return storage.values.first { $0.day == start }
    }

    public func logs(in interval: DateInterval?) async throws -> [EveningLog] {
        storage.values
            .filter { log in interval.map { $0.contains(log.day) } ?? true }
            .sorted { $0.day > $1.day }
    }

    public func save(_ log: EveningLog) async throws {
        if let existing = storage.values.first(where: { $0.day == log.day && $0.id != log.id }) {
            storage[existing.id] = nil
        }
        storage[log.id] = log
    }

    public func delete(id: UUID) async throws {
        storage[id] = nil
    }
}
