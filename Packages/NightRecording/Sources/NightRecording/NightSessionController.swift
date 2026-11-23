#if os(iOS)
import AVFoundation
import Foundation
import SleepDomain
import UIKit

/// Cycle de vie d'une nuit avec écoute : micro écran verrouillé, tranches, niveau, mouvements,
/// coupures et reprise, point de reprise chaque minute, Live Activity.
@MainActor
public final class NightSessionController: NightRecordingService {
    private let lifecycle: SessionLifecycle
    private let recordings: any RecordingRepository
    private let events: any NightEventRepository
    private let storage: RecordingStorage
    private let journal: any DiagnosticJournal
    private let quality: AudioQuality
    private let checkpoints: CheckpointStore

    private let engine = AVAudioEngine()
    private let interruptions = InterruptionMonitor()
    private let liveActivity = NightActivityController()
    private var pipeline: CapturePipeline?
    private var motion: MotionSampler?
    private var heartbeat: Task<Void, Never>?
    private var beats = 0
    private var tapInstalled = false
    private var alarm: NightAlarm?
    private var pendingGap: (start: Date, cause: RecordingGap.Cause)? {
        didSet { status.cut = pendingGap.map { ListeningCut(start: $0.start, cause: $0.cause) } }
    }
    private var continuations: [UUID: AsyncStream<NightStatus>.Continuation] = [:]
    private var status = NightStatus.idle {
        didSet { broadcast() }
    }

    public init(
        lifecycle: SessionLifecycle,
        recordings: any RecordingRepository,
        events: any NightEventRepository,
        storage: RecordingStorage,
        journal: any DiagnosticJournal,
        quality: AudioQuality = .standard
    ) {
        self.lifecycle = lifecycle
        self.recordings = recordings
        self.events = events
        self.storage = storage
        self.journal = journal
        self.quality = quality
        self.checkpoints = CheckpointStore(fileURL: storage.checkpointURL)
    }

    // MARK: - Service

    public func start(kind: SessionKind, mode: RecordingMode, alarm: NightAlarm?) async throws -> SleepSession {
        if let running = try await lifecycle.running() {
            return running
        }
        if mode != .off {
            guard await AVAudioApplication.requestRecordPermission() else { throw RecordingError.permissionDenied }
        }
        let session = try await lifecycle.start(kind: kind, mode: mode)
        self.alarm = alarm
        status = NightStatus(session: session, mode: mode, alarm: alarm)
        if mode != .off {
            do {
                try startListening(session: session, mode: mode, resume: nil)
            } catch {
                status.needsResume = true
                journal.record("Écoute impossible au démarrage : \(error.localizedDescription)")
            }
        }
        status.liveActivityEnabled = liveActivity.start(session: session, alarm: alarm?.date)
        writeCheckpoint(sessionID: session.id)
        startHeartbeat(sessionID: session.id)
        UIDevice.current.isBatteryMonitoringEnabled = true
        journal.record("Nuit démarrée · mode \(mode.rawValue) · batterie \(NightSessionController.batteryText()) · volume \(Int((AVAudioSession.sharedInstance().outputVolume * 100).rounded())) %")
        return session
    }

    @discardableResult
    public func stop() async throws -> SleepSession? {
        guard let session = try await lifecycle.running() else { return nil }
        stopListening()
        if let remaining = pipeline?.closeEvents(), !remaining.isEmpty {
            try? await events.save(remaining)
            status.eventCount += remaining.count
        }
        if let last = pipeline?.finish() {
            try? await recordings.save(last)
        }
        pipeline = nil
        await closePendingGap()
        liveActivity.end()
        checkpoints.clear()
        let finished = try await lifecycle.stop(id: session.id)
        journal.record("Nuit arrêtée · \(status.segmentCount) tranches · \(status.eventCount) événements · batterie \(NightSessionController.batteryText())")
        alarm = nil
        status = NightStatus(
            session: finished,
            mode: status.mode,
            segmentCount: status.segmentCount,
            recordedBytes: status.recordedBytes,
            eventCount: status.eventCount,
            gaps: status.gaps
        )
        return finished
    }

    public func resume() async {
        guard let session = status.session, session.state == .running, status.mode != .off else { return }
        do {
            if let pipeline {
                try AVAudioSession.sharedInstance().setActive(true)
                if !engine.isRunning {
                    try installTap(pipeline: pipeline)
                }
            } else {
                try startListening(session: session, mode: status.mode, resume: checkpoints.read())
            }
            status.isListening = true
            status.needsResume = false
            await closePendingGap()
            journal.record("Écoute reprise")
        } catch {
            status.needsResume = true
            journal.record("Reprise impossible : \(error.localizedDescription)")
        }
    }

    public func currentStatus() async -> NightStatus {
        status
    }

    public func statusUpdates() async -> AsyncStream<NightStatus> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<NightStatus>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.yield(status)
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.continuations[id] = nil
            }
        }
        return stream
    }

    public func recoverIfNeeded() async {
        let running = try? await lifecycle.running()
        let checkpoint = checkpoints.read()
        if let running, checkpoint?.sessionID == running.id {
            alarm = checkpoint?.alarm
        }
        switch RecoveryPlanner.plan(checkpoint: checkpoint, running: running, now: Date()) {
        case .nothing:
            if let running {
                status = NightStatus(session: running, mode: running.recordingMode, alarm: alarm)
            } else {
                checkpoints.clear()
                liveActivity.endStale()
            }
        case .resume(let gap):
            guard let running else { return }
            try? await recordings.save(gap)
            status = NightStatus(session: running, mode: running.recordingMode, gaps: [gap], alarm: alarm)
            journal.record("Nuit reprise après une fermeture de l'app · trou de \(Int(gap.duration / 60)) min")
            if running.recordingMode != .off {
                do {
                    try startListening(session: running, mode: running.recordingMode, resume: checkpoints.read())
                } catch {
                    status.needsResume = true
                    journal.record("Reprise de l'écoute impossible : \(error.localizedDescription)")
                }
            }
            liveActivity.endStale()
            status.liveActivityEnabled = liveActivity.start(session: running, alarm: alarm?.date)
            writeCheckpoint(sessionID: running.id)
            startHeartbeat(sessionID: running.id)
        case .close(let end, let gap):
            guard let running else { return }
            try? await recordings.save(gap)
            let closed = try? await lifecycle.close(id: running.id, at: end)
            checkpoints.clear()
            alarm = nil
            liveActivity.endStale()
            journal.record("Nuit interrompue, terminée à la dernière minute connue")
            status = NightStatus(session: closed, mode: running.recordingMode, gaps: [gap])
        }
    }

    // MARK: - Écoute

    private func startListening(session: SleepSession, mode: RecordingMode, resume: Checkpoint?) throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
        try audio.setActive(true)
        let layout = SegmentLayout(sessionID: session.id, start: session.times.bedtime ?? session.createdAt)
        let pipeline = try CapturePipeline(storage: storage, layout: layout, mode: mode, quality: quality, resume: resume) { format, start in
            SoundClassifier(format: format, start: start)
        }
        try installTap(pipeline: pipeline)
        self.pipeline = pipeline
        if motion == nil {
            motion = try? MotionSampler(fileURL: storage.url(for: layout.relativeMotionPath), start: layout.start)
            motion?.start()
        }
        interruptions.start(engine: engine) { [weak self] event in
            self?.handle(event)
        }
        status.isListening = true
        status.needsResume = false
    }

    private func installTap(pipeline: CapturePipeline) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecordingError.microphoneUnavailable }
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        let journal = self.journal
        guard let processor = TapProcessor(
            inputFormat: format,
            pipeline: pipeline,
            deliver: { [weak self] output in
                Task { @MainActor in
                    await self?.receive(output)
                }
            },
            report: { error in
                journal.record("Écriture audio impossible : \(error.localizedDescription)")
            }
        ) else { throw RecordingError.unsupportedFormat }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            processor.handle(buffer)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    private func stopListening() {
        heartbeat?.cancel()
        heartbeat = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        interruptions.stop()
        motion?.stop()
        motion = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        status.isListening = false
    }

    private func receive(_ output: CapturePipeline.Output) async {
        if let last = output.levels.last {
            status.currentLevelDb = last.meanDb
        }
        for segment in output.finishedSegments {
            try? await recordings.save(segment)
            status.segmentCount += 1
            status.recordedBytes += segment.byteSize
        }
        if !output.events.isEmpty {
            try? await events.save(output.events)
            status.eventCount += output.events.count
        }
    }

    private func handle(_ event: AudioInterruption) {
        switch event {
        case .began(let cause):
            guard pendingGap == nil else { return }
            pendingGap = (Date(), cause)
            if let segment = pipeline?.interrupt() {
                let recordings = self.recordings
                Task { try? await recordings.save(segment) }
            }
            status.isListening = false
            journal.record("Coupure de l'écoute : \(cause.rawValue)")
        case .ended:
            Task { await resume() }
        case .engineConfigurationChanged:
            guard status.isRunning, status.mode != .off else { return }
            journal.record("Configuration audio modifiée : redémarrage de l'écoute")
            Task { await resume() }
        case .mediaServicesReset:
            pendingGap = pendingGap ?? (Date(), .systemStop)
            journal.record("Services audio d'iOS réinitialisés")
            Task { await resume() }
        }
    }

    private func closePendingGap() async {
        guard let pending = pendingGap, let session = status.session else { return }
        pendingGap = nil
        let gap = RecordingGap(sessionID: session.id, start: pending.start, end: Date(), cause: pending.cause)
        try? await recordings.save(gap)
        status.gaps.append(gap)
    }

    // MARK: - Battement chaque minute

    private func startHeartbeat(sessionID: UUID) {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.beat(sessionID: sessionID)
            }
        }
    }

    private func beat(sessionID: UUID) async {
        beats += 1
        writeCheckpoint(sessionID: sessionID)
        if beats % 30 == 0 {
            journal.record("Toujours à l'écoute · \(status.segmentCount) tranches · batterie \(NightSessionController.batteryText())")
        }
        if status.mode != .off, status.isListening, !engine.isRunning {
            pendingGap = pendingGap ?? (Date(), .systemStop)
            status.isListening = false
            journal.record("L'écoute s'est arrêtée sans prévenir")
            await resume()
        }
    }

    /// Point de reprise : dernière minute connue, rangs de reprise et réveil prévu.
    private func writeCheckpoint(sessionID: UUID) {
        let checkpoint = Checkpoint(
            sessionID: sessionID,
            lastBeat: Date(),
            nextSegmentIndex: pipeline?.nextSegmentIndex ?? 1,
            levelSeconds: pipeline?.nextLevelSecond ?? 0,
            alarm: alarm
        )
        try? checkpoints.write(checkpoint)
    }

    private func broadcast() {
        for continuation in continuations.values {
            continuation.yield(status)
        }
    }

    static func batteryText() -> String {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        let percent = level >= 0 ? "\(Int((level * 100).rounded())) %" : "inconnue"
        switch device.batteryState {
        case .charging: return "\(percent) en charge"
        case .full: return "\(percent) pleine"
        case .unplugged: return "\(percent) sur batterie"
        default: return percent
        }
    }
}
#endif
