import AVFoundation
import Foundation
import SleepDomain
import Testing
@testable import NightRecording

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nocturne-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Un bloc de sinusoïde mono au format de la tranche.
private func sine(format: AVAudioFormat, seconds: Double, amplitude: Float) -> AVAudioPCMBuffer {
    let frames = AVAudioFrameCount(format.sampleRate * seconds)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let channel = buffer.floatChannelData![0]
    for index in 0..<Int(frames) {
        channel[index] = amplitude * sin(2 * Float.pi * 440 * Float(index) / Float(format.sampleRate))
    }
    return buffer
}

@Suite("Écoute · niveau sonore")
struct LevelTests {
    @Test("Une sinusoïde d'amplitude 1 donne environ -3 dBFS")
    func sineLevel() {
        var meter = LevelMeter(sampleRate: 1_000)
        let samples = (0..<2_000).map { sin(2 * Float.pi * 50 * Float($0) / 1_000) }
        let seconds = meter.add(samples)

        #expect(seconds.count == 2)
        #expect(seconds.map(\.second) == [0, 1])
        #expect(abs(seconds[0].meanDb + 3.01) < 0.1)
        #expect(seconds[0].maxDb >= seconds[0].meanDb)
    }

    @Test("Le silence vaut -120 dB et les secondes se découpent entre les blocs")
    func silenceAndSplitting() {
        var meter = LevelMeter(sampleRate: 100)
        #expect(meter.add([Float](repeating: 0, count: 60)).isEmpty)
        let finished = meter.add([Float](repeating: 0, count: 60))

        #expect(finished.count == 1)
        #expect(finished[0].meanDb == LevelMeter.silence)
        #expect(meter.flush()?.second == 1)
    }

    @Test("Série binaire : relue à l'identique, trous marqués")
    func seriesRoundTrip() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("niveaux.ncls")
        let start = Date(timeIntervalSince1970: 1_795_300_000)

        let writer = try LevelSeriesWriter(fileURL: url, start: start)
        try writer.append([LevelSecond(second: 0, meanDb: -60, maxDb: -40), LevelSecond(second: 1, meanDb: -55.5, maxDb: -30)])
        try writer.append([LevelSecond(second: 4, meanDb: -70, maxDb: -65)])
        try writer.close()

        let series = try LevelSeries.read(Data(contentsOf: url))
        #expect(series.start == start)
        #expect(series.means == [-60, -55.5, nil, nil, -70])
        #expect(series.peaks.first == -40)

        let resumed = try LevelSeriesWriter(resuming: url)
        try resumed.append([LevelSecond(second: 6, meanDb: -50, maxDb: -50)])
        try resumed.close()
        #expect(try LevelSeries.read(Data(contentsOf: url)).means.count == 7)
    }

    @Test("Un fichier qui n'est pas une série est refusé")
    func badFile() {
        #expect(throws: LevelSeries.ReadError.badMagic) {
            try LevelSeries.read(Data(repeating: 1, count: 20))
        }
    }
}

@Suite("Écoute · tranches et reprise")
struct SegmentTests {
    @Test("Rangement des fichiers d'une nuit")
    func layout() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 23, minute: 22))!
        let layout = SegmentLayout(sessionID: id, start: start, calendar: calendar)

        #expect(layout.relativeSegmentPath(index: 7) == "Recordings/2026-11-22/00000000-0000-0000-0000-000000000001/tranche-007.m4a")
        #expect(SegmentLayout.needsRotation(segmentStart: start, now: start.addingTimeInterval(300)))
        #expect(!SegmentLayout.needsRotation(segmentStart: start, now: start.addingTimeInterval(299)))
    }

    @Test("Écriture AAC en tranches, avec rotation")
    func writeSegments() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date(timeIntervalSince1970: 1_795_300_000)
        let layout = SegmentLayout(sessionID: UUID(), start: start)
        let writer = try SegmentWriter(root: root, layout: layout, quality: .standard, segmentDuration: 1)

        let block = sine(format: writer.processingFormat, seconds: 0.5, amplitude: 0.3)
        #expect(try writer.append(block, at: start) == nil)
        #expect(try writer.append(block, at: start.addingTimeInterval(0.5)) == nil)
        let first = try #require(try writer.append(block, at: start.addingTimeInterval(1.0)))
        let second = try #require(writer.finish())

        #expect(first.index == 1)
        #expect(first.state == .complete)
        #expect(abs(first.duration - 1.0) < 0.01)
        #expect(first.byteSize > 0)
        #expect(second.index == 2)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(second.relativePath).path))
    }

    @Test("Point de reprise : écrit, relu, effacé")
    func checkpointStore() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CheckpointStore(fileURL: folder.appendingPathComponent("reprise.json"))
        let checkpoint = Checkpoint(sessionID: UUID(), lastBeat: Date(timeIntervalSince1970: 1_795_300_000), nextSegmentIndex: 12, levelSeconds: 3_300)

        try store.write(checkpoint)
        #expect(store.read() == checkpoint)
        store.clear()
        #expect(store.read() == nil)
    }

    @Test("Reprise : trou noté depuis le dernier battement, nuit trop ancienne terminée")
    func recovery() {
        let start = Date(timeIntervalSince1970: 1_795_300_000)
        let session = SleepSession(state: .running, detected: SessionTimes(bedtime: start))
        let beat = start.addingTimeInterval(3_600)
        let checkpoint = Checkpoint(sessionID: session.id, lastBeat: beat, nextSegmentIndex: 13, levelSeconds: 3_600)

        let soon = RecoveryPlanner.plan(checkpoint: checkpoint, running: session, now: beat.addingTimeInterval(600))
        guard case .resume(let gap) = soon else {
            Issue.record("Reprise attendue")
            return
        }
        #expect(gap.start == beat)
        #expect(gap.cause == .appTerminated)
        #expect(gap.duration == 600)

        let late = RecoveryPlanner.plan(checkpoint: checkpoint, running: session, now: beat.addingTimeInterval(4 * 3_600))
        guard case .close(let end, _) = late else {
            Issue.record("Fin de nuit attendue")
            return
        }
        #expect(end == beat)
        #expect(RecoveryPlanner.plan(checkpoint: nil, running: nil, now: beat) == .nothing)
    }
}
