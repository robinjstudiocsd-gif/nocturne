import Foundation
import SleepDomain
import SwiftData

/// Première version du schéma de la base.
/// Tant qu'aucune version de l'app n'est installée, ce schéma peut encore évoluer ;
/// après la première installation, chaque évolution ajoutera une version et une étape de migration.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [SleepSessionRecord.self, EveningLogRecord.self]
    }

    /// Une nuit ou une sieste, telle qu'elle est rangée dans la base.
    @Model
    public final class SleepSessionRecord {
        @Attribute(.unique) public var id: UUID
        public var kindRaw: String
        public var stateRaw: String
        public var detectedBedtime: Date?
        public var detectedSleepOnset: Date?
        public var detectedWake: Date?
        public var detectedGetUp: Date?
        public var correctedBedtime: Date?
        public var correctedSleepOnset: Date?
        public var correctedWake: Date?
        public var correctedGetUp: Date?
        public var primarySourceRaw: String
        public var recordingModeRaw: String
        public var analysisVersion: Int?
        public var comment: String?
        public var mood: Int?
        public var energy: Int?
        /// Réveils de la nuit, encodés en JSON.
        public var wakeEpisodesData: Data?
        public var createdAt: Date
        public var referenceDate: Date

        public init(session: SleepSession) {
            id = session.id
            kindRaw = session.kind.rawValue
            stateRaw = session.state.rawValue
            detectedBedtime = session.detected.bedtime
            detectedSleepOnset = session.detected.sleepOnset
            detectedWake = session.detected.wake
            detectedGetUp = session.detected.getUp
            correctedBedtime = session.corrected.bedtime
            correctedSleepOnset = session.corrected.sleepOnset
            correctedWake = session.corrected.wake
            correctedGetUp = session.corrected.getUp
            primarySourceRaw = session.primarySource.rawValue
            recordingModeRaw = session.recordingMode.rawValue
            analysisVersion = session.analysisVersion
            comment = session.comment
            mood = session.feeling?.mood
            energy = session.feeling?.energy
            wakeEpisodesData = try? JSONEncoder().encode(session.wakeEpisodes)
            createdAt = session.createdAt
            referenceDate = session.referenceDate
        }
    }

    /// Un journal du soir, tel qu'il est rangé dans la base.
    @Model
    public final class EveningLogRecord {
        @Attribute(.unique) public var id: UUID
        public var day: Date
        public var caffeineRaw: String?
        public var lastCaffeine: Date?
        public var exerciseRaw: String?
        public var exerciseEnd: Date?
        public var screensRaw: String?
        public var stress: Int?
        public var mealRaw: String?
        public var mealEnd: Date?
        public var note: String?

        public init(log: EveningLog) {
            id = log.id
            day = log.day
            caffeineRaw = log.caffeine?.rawValue
            lastCaffeine = log.lastCaffeine
            exerciseRaw = log.exercise?.rawValue
            exerciseEnd = log.exerciseEnd
            screensRaw = log.screens?.rawValue
            stress = log.stress
            mealRaw = log.meal?.rawValue
            mealEnd = log.mealEnd
            note = log.note
        }
    }
}

public typealias SleepSessionRecord = SchemaV1.SleepSessionRecord
public typealias EveningLogRecord = SchemaV1.EveningLogRecord

extension SchemaV1.SleepSessionRecord {
    /// La session du domaine correspondant à cet enregistrement.
    var session: SleepSession {
        let feeling: WakeFeeling?
        if let mood, let energy {
            feeling = WakeFeeling(mood: mood, energy: energy)
        } else {
            feeling = nil
        }
        return SleepSession(
            id: id,
            kind: SessionKind(rawValue: kindRaw) ?? .night,
            state: SessionState(rawValue: stateRaw) ?? .manual,
            detected: SessionTimes(bedtime: detectedBedtime, sleepOnset: detectedSleepOnset, wake: detectedWake, getUp: detectedGetUp),
            corrected: SessionTimes(bedtime: correctedBedtime, sleepOnset: correctedSleepOnset, wake: correctedWake, getUp: correctedGetUp),
            primarySource: DataSource(rawValue: primarySourceRaw) ?? .manual,
            recordingMode: RecordingMode(rawValue: recordingModeRaw) ?? .continuous,
            analysisVersion: analysisVersion,
            comment: comment,
            feeling: feeling,
            wakeEpisodes: wakeEpisodesData.flatMap { try? JSONDecoder().decode([WakeEpisode].self, from: $0) } ?? [],
            createdAt: createdAt
        )
    }

    /// Recopie une session du domaine dans cet enregistrement (l'identifiant ne change pas).
    func apply(_ session: SleepSession) {
        kindRaw = session.kind.rawValue
        stateRaw = session.state.rawValue
        detectedBedtime = session.detected.bedtime
        detectedSleepOnset = session.detected.sleepOnset
        detectedWake = session.detected.wake
        detectedGetUp = session.detected.getUp
        correctedBedtime = session.corrected.bedtime
        correctedSleepOnset = session.corrected.sleepOnset
        correctedWake = session.corrected.wake
        correctedGetUp = session.corrected.getUp
        primarySourceRaw = session.primarySource.rawValue
        recordingModeRaw = session.recordingMode.rawValue
        analysisVersion = session.analysisVersion
        comment = session.comment
        mood = session.feeling?.mood
        energy = session.feeling?.energy
        wakeEpisodesData = try? JSONEncoder().encode(session.wakeEpisodes)
        createdAt = session.createdAt
        referenceDate = session.referenceDate
    }
}

extension SchemaV1.EveningLogRecord {
    var log: EveningLog {
        var log = EveningLog(
            id: id,
            day: day,
            caffeine: caffeineRaw.flatMap(EveningLog.Caffeine.init(rawValue:)),
            lastCaffeine: lastCaffeine,
            exercise: exerciseRaw.flatMap(EveningLog.Exercise.init(rawValue:)),
            exerciseEnd: exerciseEnd,
            screens: screensRaw.flatMap(EveningLog.Screens.init(rawValue:)),
            stress: stress,
            meal: mealRaw.flatMap(EveningLog.Meal.init(rawValue:)),
            mealEnd: mealEnd,
            note: note
        )
        // Le jour est déjà ramené au début de la journée : on le garde tel quel.
        log.day = day
        return log
    }

    func apply(_ log: EveningLog) {
        day = log.day
        caffeineRaw = log.caffeine?.rawValue
        lastCaffeine = log.lastCaffeine
        exerciseRaw = log.exercise?.rawValue
        exerciseEnd = log.exerciseEnd
        screensRaw = log.screens?.rawValue
        stress = log.stress
        mealRaw = log.meal?.rawValue
        mealEnd = log.mealEnd
        note = log.note
    }
}

/// Plan de migration : vide en V1, une étape par nouvelle version du schéma.
public enum NocturneMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
