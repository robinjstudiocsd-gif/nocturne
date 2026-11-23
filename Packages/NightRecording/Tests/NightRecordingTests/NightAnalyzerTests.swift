import Foundation
import SleepAnalysis
import SleepDomain
import Testing
@testable import NightRecording

@Suite("Analyse d'une nuit enregistrée")
struct NightAnalyzerTests {
    private let bedtime = Date(timeIntervalSince1970: 1_795_300_000)

    /// Une heure : 5 min agitées au coucher, trois retournements, 5 min de lever ; sons calmes.
    private func recordNight(levelsDelay: Int = 0) throws -> (storage: RecordingStorage, session: SleepSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nocturne-analyse-\(UUID().uuidString)", isDirectory: true)
        let storage = RecordingStorage(root: root)
        let end = bedtime.addingTimeInterval(3_600)
        let session = SleepSession(state: .finished, detected: SessionTimes(bedtime: bedtime, wake: end, getUp: end))
        let layout = SegmentLayout(sessionID: session.id, start: bedtime)
        _ = try storage.prepareFolder(for: layout)

        let levels = try LevelSeriesWriter(fileURL: storage.url(for: layout.relativeLevelsPath), start: bedtime.addingTimeInterval(Double(levelsDelay)))
        try levels.append((0..<(3_600 - levelsDelay)).map { LevelSecond(second: $0, meanDb: -60, maxDb: -59) })
        try levels.close()

        let motion = try MotionSeriesWriter(fileURL: storage.url(for: layout.relativeMotionPath), start: bedtime)
        try motion.append((0..<120).map { index in
            let moving = index < 10 || index >= 110
            let turning = [40, 60, 80].contains(index)
            return MotionWindow(index: index, activity: moving ? 30 : (turning ? 26 : 6))
        })
        try motion.close()
        return (storage, session)
    }

    @Test("Les fichiers de la nuit donnent l'endormissement et le réveil")
    func profileFromFiles() throws {
        let night = try recordNight()
        defer { try? FileManager.default.removeItem(at: night.storage.root) }

        let profile = try #require(NightAnalyzer(storage: night.storage).profile(for: night.session, events: []))

        #expect(profile.usedMotion)
        #expect(profile.usedSound)
        #expect(profile.reliability == .medium)
        #expect(profile.sleepOnset == bedtime.addingTimeInterval(5 * 60))
        #expect(profile.wake == bedtime.addingTimeInterval(55 * 60))
        #expect(profile.wakeEpisodes.isEmpty)
        #expect(NightAnalyzer.journalLine(profile).contains("mouvements et son"))
    }

    @Test("Profils relus à la demande, seulement pour une nuit enregistrée et terminée")
    func recordedProfiles() async throws {
        let night = try recordNight()
        defer { try? FileManager.default.removeItem(at: night.storage.root) }
        let provider = RecordedNightProfiles(storage: night.storage, events: InMemoryNightEventRepository())

        let profile = await provider.profile(for: night.session)
        #expect(profile?.sleepOnset == bedtime.addingTimeInterval(5 * 60))

        var running = night.session
        running.state = .running
        #expect(await provider.profile(for: running) == nil)
    }

    @Test("Un niveau sonore commencé en retard est recalé sur le coucher")
    func alignment() throws {
        let night = try recordNight(levelsDelay: 30)
        defer { try? FileManager.default.removeItem(at: night.storage.root) }

        let input = try #require(NightAnalyzer(storage: night.storage).input(for: night.session, events: []))

        #expect(input.peaks.count == 3_600)
        #expect(input.peaks[29] == nil)
        #expect(input.peaks[30] == Float(-59))
        #expect(input.motion.count == 120)
        #expect(NightAnalyzer.align([1, 2, 3], offset: -1) == [Float?]([2, 3]))
    }

    @Test("Déverrouillages : gardés seulement si iOS a signalé un verrouillage ; le dernier se ferme à l'arrêt")
    func unlocks() throws {
        var log = UnlockLog()
        log.unlocked(at: bedtime)
        log.locked(at: bedtime.addingTimeInterval(60))
        log.unlocked(at: bedtime.addingTimeInterval(3_000))
        #expect(log.periods == [DateInterval(start: bedtime, end: bedtime.addingTimeInterval(60))])

        var withoutCode = UnlockLog()
        withoutCode.unlocked(at: bedtime)
        withoutCode.finish(at: bedtime.addingTimeInterval(3_600))
        #expect(withoutCode.periods.count == 1)
        #expect(withoutCode.usablePeriods.isEmpty)

        let night = try recordNight()
        defer { try? FileManager.default.removeItem(at: night.storage.root) }
        let folder = try #require(night.storage.folder(sessionID: night.session.id))
        try log.write(to: folder)
        #expect(UnlockLog.read(from: folder) == log)

        let input = try #require(NightAnalyzer(storage: night.storage).input(for: night.session, events: []))
        #expect(input.unlocks == [
            DateInterval(start: bedtime, end: bedtime.addingTimeInterval(60)),
            DateInterval(start: bedtime.addingTimeInterval(3_000), end: bedtime.addingTimeInterval(3_600))
        ])
    }

    @Test("Une nuit sans dossier n'a que ses horaires ; une nuit sans horaires n'est pas analysée")
    func missingFiles() {
        let storage = RecordingStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("vide-\(UUID().uuidString)"))
        let end = bedtime.addingTimeInterval(3_600)
        let session = SleepSession(state: .finished, detected: SessionTimes(bedtime: bedtime, wake: end, getUp: end))
        let analyzer = NightAnalyzer(storage: storage)

        #expect(analyzer.input(for: session, events: [])?.peaks.isEmpty == true)
        #expect(analyzer.profile(for: session, events: [])?.sleepOnset == nil)
        #expect(analyzer.profile(for: SleepSession(state: .manual), events: []) == nil)
    }
}
