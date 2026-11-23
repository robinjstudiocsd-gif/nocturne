import Foundation
import SleepDomain
import Testing
@testable import NightRecording

@Suite("Événements · détection")
struct EventDetectionTests {
    @Test("Bruit de fond : suit la pièce, ignore les pics")
    func noiseFloor() {
        var tracker = NoiseFloorTracker()
        var floor: Float = 0
        for second in 0..<120 {
            floor = tracker.add(second % 10 == 0 ? -20 : -60)
        }
        #expect(floor == -60)

        for _ in 0..<300 {
            floor = tracker.add(-45)
        }
        #expect(floor == -45)
    }

    @Test("Déclenchement : au-dessus du seuil, quelques secondes après, et une seconde par minute")
    func trigger() {
        var trigger = DetectionTrigger(threshold: 10, holdSeconds: 3)
        let steps: [(second: Int, level: Float)] = [(0, -60), (1, -58), (10, -45), (13, -60), (14, -60), (72, -60), (73, -60)]
        var answers: [Bool] = []
        for step in steps {
            answers.append(trigger.shouldAnalyze(second: step.second, level: step.level, floor: -60))
        }
        #expect(answers == [true, false, true, true, false, false, true])
    }

    @Test("Étiquettes d'Apple regroupées en types")
    func labels() {
        #expect(SoundLabelMap.kind(for: "snoring") == .snoring)
        #expect(SoundLabelMap.kind(for: "Cough") == .cough)
        #expect(SoundLabelMap.kind(for: "whispering") == .speech)
        #expect(SoundLabelMap.kind(for: "dog_bark") == .external)
        #expect(SoundLabelMap.kind(for: "breathing") == .breathing)
        #expect(SoundLabelMap.kind(for: "silence") == nil)
        #expect(SoundLabelMap.kind(for: "accordion") == .unusual)
    }

    @Test("Regroupement : détections proches fusionnées, types séparés, fin de nuit")
    func aggregator() {
        let session = UUID()
        let start = Date(timeIntervalSince1970: 1_795_300_000)
        var aggregator = EventAggregator(sessionID: session)
        var closed: [NightEvent] = []

        // Ronflements toutes les 4 s pendant une minute : un seul événement.
        for offset in stride(from: 0, through: 60, by: 4) {
            closed += aggregator.add(SoundDetection(time: start.addingTimeInterval(TimeInterval(offset)), kind: .snoring, confidence: offset == 20 ? 0.95 : 0.7, intensity: Double(offset) / 4))
        }
        #expect(closed.isEmpty)

        // Une parole au milieu ne coupe pas le ronflement.
        closed += aggregator.add(SoundDetection(time: start.addingTimeInterval(62), kind: .speech, confidence: 0.6, intensity: 8))
        // Deux minutes plus tard, un nouveau ronflement : le premier et la parole sont refermés.
        closed += aggregator.add(SoundDetection(time: start.addingTimeInterval(200), kind: .snoring, confidence: 0.8, intensity: 10))

        #expect(closed.map(\.kind) == [.snoring, .speech])
        let snore = closed[0]
        #expect(snore.start == start)
        #expect(snore.duration == 61)
        #expect(snore.confidence == 0.95)
        #expect(snore.intensity == 15)
        #expect(snore.sessionID == session)

        let last = aggregator.flush()
        #expect(last.count == 1)
        #expect(last.first?.start == start.addingTimeInterval(200))
        let again = aggregator.flush()
        #expect(again.isEmpty)
    }
}
