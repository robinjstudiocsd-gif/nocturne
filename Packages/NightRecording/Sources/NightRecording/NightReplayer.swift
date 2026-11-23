#if os(iOS)
import AVFoundation
import CoreMedia
import Foundation
import SleepDomain

/// Réécoute de la nuit entière : les tranches de 5 minutes sont posées sur la ligne du temps de la nuit,
/// les trous restent silencieux. Vitesse de lecture, saut des silences, export d'une minute.
@MainActor
public final class NightReplayer: NightReplaying {
    /// Nombre de colonnes de la frise.
    public static let columnCount = 160

    private let storage: RecordingStorage
    private let recordings: any RecordingRepository
    private let events: any NightEventRepository
    private var player: AVPlayer?
    private var composition: AVMutableComposition?
    private var timeObserver: Any?
    private var timeline: NightTimeline?
    private var startedSession = false
    private var state = ReplayState() {
        didSet { broadcast() }
    }
    private var continuations: [UUID: AsyncStream<ReplayState>.Continuation] = [:]

    public init(storage: RecordingStorage, recordings: any RecordingRepository, events: any NightEventRepository) {
        self.storage = storage
        self.recordings = recordings
        self.events = events
    }

    public func load(_ session: SleepSession) async throws -> NightTimeline {
        stop()
        let start = session.detected.bedtime ?? session.createdAt
        let segments = try await recordings.segments(sessionID: session.id).sorted { $0.start < $1.start }
        let gaps = try await recordings.gaps(sessionID: session.id)
        let nightEvents = try await events.events(sessionID: session.id)

        var peaks: [Float?] = []
        var means: [Float?] = []
        if let folder = storage.folder(sessionID: session.id),
           let data = try? Data(contentsOf: folder.appendingPathComponent("niveaux.ncls")),
           let series = try? LevelSeries.read(data) {
            peaks = series.peaks
            means = series.means
        }
        let stopTime = session.detected.wake ?? segments.last?.end ?? start
        let duration = max(TimeInterval(peaks.count), stopTime.timeIntervalSince(start), 1)

        let composition = await NightComposition.build(segments: segments, start: start, storage: storage)?.composition
        let hasAudio = composition != nil

        let busy = nightEvents.map { event -> ClosedRange<TimeInterval> in
            let from = max(0, event.start.timeIntervalSince(start))
            return from...max(from, event.end.timeIntervalSince(start))
        }
        let quiet = TimelineBuilder.floor(means).map { TimelineBuilder.quietRanges(peaks: peaks, floor: $0, busy: busy) } ?? []
        let timeline = NightTimeline(
            start: start,
            duration: duration,
            columns: TimelineBuilder.columns(peaks, count: Self.columnCount),
            events: nightEvents,
            gaps: gaps,
            quietRanges: quiet,
            hasAudio: hasAudio
        )
        self.timeline = timeline
        self.composition = composition
        if let composition {
            let item = AVPlayerItem(asset: composition)
            item.audioTimePitchAlgorithm = .timeDomain
            let player = AVPlayer(playerItem: item)
            self.player = player
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    self?.tick(time.seconds)
                }
            }
        }
        state = ReplayState(position: 0, duration: duration, isPlaying: false, rate: state.rate, skipsSilences: state.skipsSilences)
        return timeline
    }

    public func updates() -> AsyncStream<ReplayState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ReplayState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.yield(state)
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.continuations[id] = nil
            }
        }
        return stream
    }

    public func play() {
        guard let player else { return }
        activateSession()
        if state.position >= state.duration - 0.5 {
            seek(to: 0)
        }
        player.rate = state.rate
        state.isPlaying = true
    }

    public func pause() {
        player?.pause()
        state.isPlaying = false
    }

    public func seek(to position: TimeInterval) {
        let target = min(max(0, position), state.duration)
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        state.position = target
    }

    public func setRate(_ rate: Float) {
        state.rate = rate
        if state.isPlaying {
            player?.rate = rate
        }
    }

    public func setSkipsSilences(_ skips: Bool) {
        state.skipsSilences = skips
    }

    public func stop() {
        player?.pause()
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player = nil
        composition = nil
        state.isPlaying = false
        deactivateSession()
    }

    public func exportPassage(around position: TimeInterval) async throws -> URL {
        guard let composition else { throw RecordingError.unsupportedFormat }
        let clock = timeline.map { SleepFormat().clock($0.date(at: position)).replacingOccurrences(of: ":", with: "h") } ?? "passage"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nocturne-\(clock).m4a")
        try await NightComposition.export(composition, from: position - 30, to: min(state.duration, position + 30), url: url)
        return url
    }

    // MARK: - Lecture

    private func tick(_ seconds: Double) {
        guard seconds.isFinite, let player else { return }
        state.position = seconds
        if state.isPlaying && player.rate == 0 && seconds >= state.duration - 0.5 {
            state.isPlaying = false
        }
        guard state.isPlaying, state.skipsSilences, let timeline else { return }
        let target = timeline.skippingQuiet(seconds)
        if target > seconds + 0.5 {
            seek(to: target)
        }
    }

    /// Lecture par le haut-parleur ; pendant une nuit en cours, la session d'écoute reste telle quelle.
    private func activateSession() {
        let audio = AVAudioSession.sharedInstance()
        if audio.category != .playAndRecord {
            try? audio.setCategory(.playback, mode: .default)
            startedSession = true
        }
        try? audio.setActive(true)
    }

    private func deactivateSession() {
        guard startedSession else { return }
        startedSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func broadcast() {
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }
}
#endif
