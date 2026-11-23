import Foundation
import Testing
@testable import SleepAnalysis
import SleepDomain

private let start = Date(timeIntervalSince1970: 1_795_000_000)

private func minutes(_ value: Double) -> Date {
    start.addingTimeInterval(value * 60)
}

/// Mouvements de la nuit : `rest` partout, sauf pour les périodes données.
private func motion(count: Int, rest: Float = 6, _ changes: [(Range<Int>, Float)] = []) -> [Float?] {
    var values = [Float?](repeating: rest, count: count)
    for (range, value) in changes {
        for index in range {
            values[index] = value
        }
    }
    return values
}

/// Sons de la nuit : bruit de fond à −60 dB chaque seconde, et des secondes bruyantes à −40 dB.
private func sound(seconds: Int, loud: [Range<Int>] = []) -> (peaks: [Float?], means: [Float?]) {
    var peaks = [Float?](repeating: -59, count: seconds)
    for range in loud {
        for second in range {
            peaks[second] = -40
        }
    }
    return (peaks, [Float?](repeating: -60, count: seconds))
}

private func event(_ kind: EventKind, from: Double, to: Double, someoneElse: Bool = false) -> NightEvent {
    NightEvent(
        sessionID: UUID(),
        kind: kind,
        start: minutes(from),
        duration: (to - from) * 60,
        confidence: 0.9,
        intensity: 20,
        isSomeoneElse: someoneElse
    )
}

@Suite("Profil de la nuit")
struct NightProfileTests {
    @Test("iPhone sur le lit : endormissement, réveil dans la nuit, réveil final ; se retourner reste « agité »")
    func onTheBed() {
        let quiet = sound(seconds: 3 * 3_600)
        let input = ProfileInput(
            start: start,
            end: minutes(180),
            motion: motion(count: 360, [(0..<20, 30), (80..<81, 26), (140..<141, 26), (200..<210, 40), (260..<261, 26), (340..<360, 30)]),
            peaks: quiet.peaks,
            means: quiet.means
        )
        let profile = NightProfiler.analyze(input)

        #expect(profile.usedMotion)
        #expect(profile.usedSound)
        #expect(profile.reliability == .medium)
        #expect(profile.source == .motion)
        #expect(profile.states.count == 360)
        #expect(profile.states[0] == .awake)
        #expect(profile.states[80] == .agitated)
        #expect(profile.states[205] == .awake)
        #expect(profile.sleepOnset == minutes(10))
        #expect(profile.wake == minutes(170))
        #expect(profile.wakeEpisodes.count == 1)
        #expect(profile.wakeEpisodes.first?.start == minutes(100))
        #expect(profile.wakeEpisodes.first?.end == minutes(105))
        #expect(profile.wakeEpisodes.first?.source == .motion)
        #expect(profile.intervals.count == 11)
        #expect(profile.intervals.first == ProfileInterval(start: minutes(0), end: minutes(10), state: .awake))
        #expect(profile.intervals.last == ProfileInterval(start: minutes(170), end: minutes(180), state: .awake))
        #expect(profile.duration(of: .agitated) == 90)
    }

    @Test("iPhone sur la table de nuit : le son seul, fiabilité faible ; parler compte comme un éveil")
    func soundOnly() {
        let noisy = sound(seconds: 3_600, loud: [0..<300])
        let input = ProfileInput(
            start: start,
            end: minutes(60),
            motion: motion(count: 120, rest: 4),
            peaks: noisy.peaks,
            means: noisy.means,
            events: [event(.speech, from: 30, to: 33)]
        )
        let profile = NightProfiler.analyze(input)

        #expect(!profile.usedMotion)
        #expect(profile.usedSound)
        #expect(profile.reliability == .low)
        #expect(profile.source == .microphone)
        #expect(profile.states[0] == .awake)
        #expect(profile.states[61] == .awake)
        #expect(profile.sleepOnset == minutes(5))
        #expect(profile.wake == minutes(60))
        #expect(profile.wakeEpisodes.map(\.start) == [minutes(30)])
        #expect(profile.wakeEpisodes.map(\.end) == [minutes(33)])
        #expect(profile.wakeEpisodes.first?.source == .microphone)
    }

    @Test("Ronflements, bruits extérieurs et sons d'une autre personne ne réveillent pas")
    func ignoredSounds() {
        let noisy = sound(seconds: 1_800, loud: [600..<900, 1_200..<1_320, 1_500..<1_560])
        var input = ProfileInput(start: start, end: minutes(30), peaks: noisy.peaks, means: noisy.means)

        let bare = NightProfiler.analyze(input)
        #expect(bare.states[20] == .awake)
        #expect(bare.states[40] == .awake)

        input.events = [
            event(.snoring, from: 10, to: 15),
            event(.external, from: 20, to: 22),
            event(.speech, from: 25, to: 26, someoneElse: true)
        ]
        let profile = NightProfiler.analyze(input)
        #expect(profile.states.allSatisfy { $0 == .calm })
        #expect(profile.sleepOnset == minutes(0))
        #expect(profile.wake == minutes(30))
        #expect(profile.wakeEpisodes.isEmpty)
    }

    @Test("Sieste : endormissement après 5 minutes de calme")
    func nap() {
        let input = ProfileInput(
            kind: .nap,
            start: start,
            end: minutes(20),
            motion: motion(count: 40, [(0..<4, 30), (12..<13, 16), (18..<19, 16), (24..<25, 16)])
        )
        let profile = NightProfiler.analyze(input)

        #expect(profile.usedMotion)
        #expect(!profile.usedSound)
        #expect(profile.reliability == .low)
        #expect(profile.states[12] == .agitated)
        #expect(profile.sleepOnset == minutes(2))
        #expect(profile.wake == minutes(20))
        #expect(profile.wakeEpisodes.isEmpty)
    }

    @Test("Sans aucune mesure : pas d'horaire deviné")
    func nothingMeasured() {
        let profile = NightProfiler.analyze(ProfileInput(start: start, end: minutes(60)))

        #expect(profile.states.count == 120)
        #expect(profile.states.allSatisfy { $0 == .unknown })
        #expect(profile.sleepOnset == nil)
        #expect(profile.wake == nil)
        #expect(profile.source == nil)
        #expect(profile.reliability == .low)
    }

    @Test("Réveils réunis par-dessus une période calme ; dernier sommeil d'au moins trois périodes")
    func runs() {
        let states: [EpochState] = [.calm, .awake, .awake, .calm, .awake, .calm, .calm, .awake]
        #expect(NightProfiler.wakeRuns(states, from: 0, to: 8) == [1..<5, 7..<8])

        let ending: [EpochState] = [.calm, .calm, .calm, .calm, .calm, .awake, .calm, .awake, .awake]
        #expect(NightProfiler.lastSleepEnd(ending, from: 0) == 5)
        #expect(NightProfiler.percentile([5, 1, 4, 2, 3], 0.5) == 3)
        #expect(NightProfiler.percentile([], 0.2) == 0)
    }
}
