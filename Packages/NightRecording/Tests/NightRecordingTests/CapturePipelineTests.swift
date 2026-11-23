import AVFoundation
import Foundation
import SleepDomain
import Testing
@testable import NightRecording

private func temporaryStorage() throws -> RecordingStorage {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nocturne-pipeline-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return RecordingStorage(root: folder)
}

private func tone(format: AVAudioFormat, seconds: Double, amplitude: Float) -> AVAudioPCMBuffer {
    let frames = AVAudioFrameCount(format.sampleRate * seconds)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let channel = buffer.floatChannelData![0]
    for index in 0..<Int(frames) {
        channel[index] = amplitude * sin(2 * Float.pi * 220 * Float(index) / Float(format.sampleRate))
    }
    return buffer
}

/// Classifieur factice : note quand il doit analyser et rend les détections qu'on lui donne.
private final class FakeClassifier: SoundClassifying, @unchecked Sendable {
    var activeSeconds: [Bool] = []
    var pending: [SoundDetection] = []
    var finished = false
    var resets = 0

    func process(_ buffer: AVAudioPCMBuffer, framePosition: AVAudioFramePosition, active: Bool) {
        activeSeconds.append(active)
    }

    func drain() -> [SoundDetection] {
        defer { pending = [] }
        return pending
    }

    func reset() {
        resets += 1
    }

    func finish() {
        finished = true
    }
}

@Suite("Écoute · traitement des blocs")
struct CapturePipelineTests {
    @Test("Mode événements : un extrait autour de chaque son, avec du son avant et après")
    func clips() throws {
        let storage = try temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let start = Date(timeIntervalSince1970: 1_795_300_000)
        let pipeline = try CapturePipeline(storage: storage, layout: SegmentLayout(sessionID: UUID(), start: start), mode: .events, quality: .standard)
        let format = pipeline.processingFormat
        var clips: [AudioSegment] = []
        for step in 0..<40 {
            let amplitude: Float = (20..<22).contains(step) ? 0.3 : 0.001
            clips += try pipeline.process(tone(format: format, seconds: 1, amplitude: amplitude), at: start.addingTimeInterval(Double(step))).finishedSegments
        }

        #expect(clips.count == 1)
        let clip = try #require(clips.first)
        #expect(clip.relativePath.hasSuffix("extrait-001.m4a"))
        #expect(clip.start == start.addingTimeInterval(15))
        #expect(clip.duration > 8 && clip.duration < 16)
        #expect(clip.byteSize > 0)
        #expect(pipeline.nextSegmentIndex == 2)
        #expect(pipeline.finish() == nil)
    }

    @Test("Événements : le classifieur écoute au-dessus du bruit de fond, les détections deviennent des événements")
    func events() throws {
        let storage = try temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let start = Date(timeIntervalSince1970: 1_795_300_000)
        let fake = FakeClassifier()
        let pipeline = try CapturePipeline(storage: storage, layout: SegmentLayout(sessionID: UUID(), start: start), mode: .events, quality: .standard) { _, _ in fake }
        let format = pipeline.processingFormat

        for step in 0..<30 {
            _ = try pipeline.process(tone(format: format, seconds: 1, amplitude: 0.001), at: start.addingTimeInterval(Double(step)))
        }
        let quietActive = fake.activeSeconds.dropFirst(2).filter { $0 }.count
        #expect(quietActive == 0)

        _ = try pipeline.process(tone(format: format, seconds: 1, amplitude: 0.3), at: start.addingTimeInterval(30))
        fake.pending = [SoundDetection(time: start.addingTimeInterval(30), kind: .cough, confidence: 0.9, intensity: 0)]
        let after = try pipeline.process(tone(format: format, seconds: 1, amplitude: 0.001), at: start.addingTimeInterval(31))
        #expect(fake.activeSeconds.last == true)
        #expect(after.events.isEmpty)

        _ = pipeline.interrupt()
        #expect(fake.resets == 1)

        let events = pipeline.closeEvents()
        #expect(fake.finished)
        #expect(events.count == 1)
        #expect(events.first?.kind == .cough)
        #expect(events.first?.start == start.addingTimeInterval(30))
        #expect((events.first?.intensity ?? 0) > 20)
    }

    @Test("Mode continu : niveau chaque seconde, tranches, puis fin propre")
    func continuous() throws {
        let storage = try temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let start = Date(timeIntervalSince1970: 1_795_300_000)
        let layout = SegmentLayout(sessionID: UUID(), start: start)
        let pipeline = try CapturePipeline(storage: storage, layout: layout, mode: .continuous, quality: .standard, segmentDuration: 2)

        var levels: [LevelSecond] = []
        var segments: [AudioSegment] = []
        for step in 0..<6 {
            let output = try pipeline.process(tone(format: pipeline.processingFormat, seconds: 1, amplitude: 0.2), at: start.addingTimeInterval(Double(step)))
            levels += output.levels
            segments += output.finishedSegments
        }
        if let last = pipeline.finish() {
            segments.append(last)
        }

        #expect(levels.map(\.second) == [0, 1, 2, 3, 4, 5])
        #expect(segments.map(\.index) == [1, 2, 3])
        #expect(pipeline.latestLevelDb != nil)
        #expect(pipeline.nextSegmentIndex == 4)
        let series = try LevelSeries.read(Data(contentsOf: storage.url(for: layout.relativeLevelsPath)))
        #expect(series.means.count == 6)
    }

    @Test("Mode événements : niveau seulement, aucune tranche d'audio")
    func eventsOnly() throws {
        let storage = try temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let start = Date(timeIntervalSince1970: 1_795_300_000)
        let pipeline = try CapturePipeline(storage: storage, layout: SegmentLayout(sessionID: UUID(), start: start), mode: .events, quality: .standard)

        let output = try pipeline.process(tone(format: pipeline.processingFormat, seconds: 1.5, amplitude: 0.2), at: start)
        #expect(output.levels.count == 1)
        #expect(output.finishedSegments.isEmpty)
        #expect(pipeline.finish() == nil)
    }

    @Test("Coupure : la tranche est tronquée, les secondes manquantes sont marquées")
    func interruption() throws {
        let storage = try temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let start = Date(timeIntervalSince1970: 1_795_300_000)
        let layout = SegmentLayout(sessionID: UUID(), start: start)
        let pipeline = try CapturePipeline(storage: storage, layout: layout, mode: .continuous, quality: .standard)

        _ = try pipeline.process(tone(format: pipeline.processingFormat, seconds: 1, amplitude: 0.2), at: start)
        let cut = try #require(pipeline.interrupt())
        #expect(cut.state == .truncated)

        _ = try pipeline.process(tone(format: pipeline.processingFormat, seconds: 1, amplitude: 0.2), at: start.addingTimeInterval(10))
        _ = pipeline.finish()

        let series = try LevelSeries.read(Data(contentsOf: storage.url(for: layout.relativeLevelsPath)))
        #expect(series.means.count == 11)
        #expect(series.means[5] == nil)
        #expect(series.means[10] != nil)
    }

    @Test("Le mode désactivé n'ouvre pas le micro")
    func offMode() throws {
        let storage = try temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.root) }
        #expect(throws: RecordingError.microphoneUnavailable) {
            try CapturePipeline(storage: storage, layout: SegmentLayout(sessionID: UUID(), start: Date()), mode: .off, quality: .standard)
        }
    }
}

@Suite("Écoute · mouvements")
struct MotionTests {
    @Test("Activité moyenne par fenêtre de 30 s")
    func accumulate() {
        let start = Date(timeIntervalSince1970: 1_795_300_000)
        var accumulator = MotionAccumulator(start: start)

        #expect(accumulator.add(x: 0, y: 0, z: 1, at: start).isEmpty)
        #expect(accumulator.add(x: 0, y: 0, z: 1.1, at: start.addingTimeInterval(10)).isEmpty)
        let finished = accumulator.add(x: 0, y: 0, z: 1, at: start.addingTimeInterval(31))

        #expect(finished.count == 1)
        #expect(finished[0].index == 0)
        #expect(abs(finished[0].activity - 50) < 0.5)
        #expect(accumulator.flush()?.index == 1)
    }

    @Test("Série des mouvements : fenêtres sans mesure marquées")
    func series() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mouvements-\(UUID().uuidString).ncms")
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = try MotionSeriesWriter(fileURL: folder, start: Date(timeIntervalSince1970: 1_795_300_000))
        try writer.append([MotionWindow(index: 0, activity: 10), MotionWindow(index: 2, activity: 300)])
        try writer.close()

        let values = try #require(MotionSeries.read(Data(contentsOf: folder)))
        #expect(values == [10, nil, 300])
    }

    @Test("Une nuit sans écoute n'est jamais « reprise »")
    func offModeRecovery() {
        let session = SleepSession(state: .running, detected: SessionTimes(bedtime: Date(timeIntervalSince1970: 1_795_300_000)), recordingMode: .off)
        #expect(RecoveryPlanner.plan(checkpoint: nil, running: session, now: Date(timeIntervalSince1970: 1_795_330_000)) == .nothing)
    }
}

@MainActor
@Suite("Conservation de l'audio")
struct AudioRetentionTests {
    @Test("Passages : 5 s avant, 20 s d'un long événement et 5 s après, fusionnés quand ils se touchent")
    func passages() {
        let start = Date(timeIntervalSince1970: 1_795_300_000)
        let session = UUID()
        let events = [
            NightEvent(sessionID: session, kind: .snoring, start: start.addingTimeInterval(100), duration: 300, confidence: 0.9, intensity: 10),
            NightEvent(sessionID: session, kind: .speech, start: start.addingTimeInterval(120), duration: 4, confidence: 0.7, intensity: 8),
            NightEvent(sessionID: session, kind: .cough, start: start.addingTimeInterval(600), duration: 2, confidence: 0.8, intensity: 12)
        ]
        #expect(AudioRetention.passages(for: events, start: start) == [95...129, 595...607])
    }

    @Test("Les nuits anciennes gardent les passages des événements, les récentes tout leur audio")
    func reduceOldNights() async throws {
        let storage = try temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let oldStart = Date(timeIntervalSince1970: 1_795_300_000)
        let newStart = oldStart.addingTimeInterval(86_400)
        let old = SleepSession(state: .finished, detected: SessionTimes(bedtime: oldStart, wake: oldStart.addingTimeInterval(12)))
        let recent = SleepSession(state: .finished, detected: SessionTimes(bedtime: newStart, wake: newStart.addingTimeInterval(12)))
        let sessions = InMemorySleepSessionRepository([old, recent])
        let recordings = InMemoryRecordingRepository()
        let events = InMemoryNightEventRepository([NightEvent(sessionID: old.id, kind: .cough, start: oldStart.addingTimeInterval(6), duration: 1, confidence: 0.9, intensity: 20)])

        var oldTranches: [AudioSegment] = []
        for (session, start) in [(old, oldStart), (recent, newStart)] {
            let writer = try SegmentWriter(root: storage.root, layout: SegmentLayout(sessionID: session.id, start: start), quality: .standard, segmentDuration: 6)
            for step in 0..<12 {
                if let finished = try writer.append(tone(format: writer.processingFormat, seconds: 1, amplitude: 0.2), at: start.addingTimeInterval(Double(step))) {
                    try await recordings.save(finished)
                    if session.id == old.id { oldTranches.append(finished) }
                }
            }
            if let last = writer.finish() {
                try await recordings.save(last)
                if session.id == old.id { oldTranches.append(last) }
            }
        }

        let retention = AudioRetention(storage: storage, sessions: sessions, recordings: recordings, events: events, journal: SilentDiagnosticJournal())
        let reduced = await retention.apply(keepingNights: 1)

        #expect(reduced == 1)
        let oldSegments = try await recordings.segments(sessionID: old.id)
        #expect(oldSegments.count == 1)
        let clip = try #require(oldSegments.first)
        #expect(clip.relativePath.hasSuffix("extrait-003.m4a"))
        #expect(clip.start == oldStart.addingTimeInterval(1))
        #expect(FileManager.default.fileExists(atPath: storage.url(for: clip.relativePath).path))
        for tranche in oldTranches {
            #expect(!FileManager.default.fileExists(atPath: storage.url(for: tranche.relativePath).path))
        }
        #expect(try await events.events(sessionID: old.id).first?.clipPath == clip.relativePath)
        #expect(try await recordings.segments(sessionID: recent.id).count == 2)
    }
}
