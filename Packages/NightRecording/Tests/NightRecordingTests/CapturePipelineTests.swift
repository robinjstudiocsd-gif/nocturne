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

@Suite("Écoute · traitement des blocs")
struct CapturePipelineTests {
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
