import AVFoundation
import UIKit

/// Écoute de la nuit : micro en continu, audio en tranches AAC de 5 min, niveau sonore,
/// un battement par minute pour repérer les trous, et gestion des coupures.
final class NightRecorder: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var startDate: Date?
    @Published private(set) var segmentCount = 0
    @Published private(set) var bytesWritten: Int64 = 0
    @Published private(set) var levelDb: Float = -90
    @Published private(set) var needsResume = false
    @Published private(set) var interruptions = 0

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()

    private let log = EventLog.shared
    private let segmentLength: TimeInterval = 300
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!

    // Utilisés sur le fil du micro.
    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var segmentStart = Date()
    private var segmentIndex = 0
    private var lastLevelPublish = Date.distantPast
    private var minuteStart = Date()
    private var minuteSum: Double = 0
    private var minuteCount = 0
    private var minuteMax: Float = -120

    private var nightFolder: URL?
    private var heartbeat: Timer?
    private var beats = 0
    private var observers: [NSObjectProtocol] = []
    private var tapInstalled = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: AlarmTone.format)
    }

    // MARK: - Démarrer et arrêter

    func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let now = Date()
        let folder = try NightStore.makeNightFolder(start: now)
        nightFolder = folder
        try Data("minute,moyenne_db,max_db\n".utf8).write(to: folder.appendingPathComponent("niveaux.csv"))
        segmentIndex = 0
        file = nil
        fileURL = nil
        minuteStart = now
        minuteSum = 0
        minuteCount = 0
        minuteMax = -120
        beats = 0

        try installTapAndStart()

        startDate = now
        segmentCount = 0
        bytesWritten = 0
        interruptions = 0
        needsResume = false
        isRunning = true
        observe()
        startHeartbeat()
        log.add("Nuit démarrée · batterie \(NightRecorder.batteryText()) · volume \(Int((session.outputVolume * 100).rounded())) % · \(NightRecorder.thermalText())")
    }

    func stop(reason: String) {
        guard isRunning else { return }
        heartbeat?.invalidate()
        heartbeat = nil
        player.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        closeSegment()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let end = Date()
        let start = startDate ?? end
        if let folder = nightFolder {
            let bytes = NightStore.summary(of: folder)?.bytes ?? bytesWritten
            NightStore.writeSummary(folder: folder, start: start, end: end, segments: segmentIndex, bytes: bytes, interruptions: interruptions)
        }
        log.add("Nuit arrêtée (\(reason)) · \(Format.duration(end.timeIntervalSince(start))) · \(segmentIndex) tranches · batterie \(NightRecorder.batteryText())")
        isRunning = false
        needsResume = false
        nightFolder = nil
    }

    func resume(automatic: Bool) {
        guard isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                try installTapAndStart()
            }
            needsResume = false
            log.add(automatic ? "Écoute reprise automatiquement" : "Écoute reprise à la main")
        } catch {
            needsResume = true
            log.add("Reprise impossible : \(error.localizedDescription)")
        }
    }

    // MARK: - Micro

    private func installTapAndStart() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "Nocturne", code: 1, userInfo: [NSLocalizedDescriptionKey: "Micro indisponible"])
        }
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        measure(buffer)
        guard let converter else { return }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var delivered = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, converted.frameLength > 0 else { return }
        do {
            if file == nil || Date().timeIntervalSince(segmentStart) >= segmentLength {
                try openNextSegment()
            }
            try file?.write(from: converted)
        } catch {
            log.add("Écriture audio impossible : \(error.localizedDescription)")
        }
    }

    private func measure(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Float = 0
        for index in 0..<count {
            let value = samples[index]
            sum += value * value
        }
        let rms = (sum / Float(count)).squareRoot()
        let db: Float = rms > 0.000_001 ? 20 * log10f(rms) : -120
        minuteSum += Double(db)
        minuteCount += 1
        minuteMax = max(minuteMax, db)

        let now = Date()
        if now.timeIntervalSince(lastLevelPublish) >= 0.5 {
            lastLevelPublish = now
            DispatchQueue.main.async { self.levelDb = db }
        }
        if now.timeIntervalSince(minuteStart) >= 60, let folder = nightFolder {
            let mean = minuteCount > 0 ? minuteSum / Double(minuteCount) : -120
            let line = "\(Int(now.timeIntervalSince1970))," + String(format: "%.1f,%.1f\n", mean, Double(minuteMax))
            NightRecorder.append(line, to: folder.appendingPathComponent("niveaux.csv"))
            minuteStart = now
            minuteSum = 0
            minuteCount = 0
            minuteMax = -120
        }
    }

    private func openNextSegment() throws {
        closeSegment()
        guard let folder = nightFolder else { return }
        segmentIndex += 1
        let url = folder.appendingPathComponent(String(format: "tranche-%03d.m4a", segmentIndex))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        fileURL = url
        segmentStart = Date()
        let index = segmentIndex
        DispatchQueue.main.async { self.segmentCount = index }
    }

    private func closeSegment() {
        guard let url = fileURL else { return }
        file = nil
        fileURL = nil
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        DispatchQueue.main.async { self.bytesWritten += Int64(size) }
    }

    // MARK: - Coupures et surveillance

    private func observe() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.log.add("Configuration audio modifiée · redémarrage de l’écoute")
            self.resume(automatic: true)
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.log.add("Services audio d’iOS réinitialisés")
            self.resume(automatic: true)
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            guard
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                reason == .oldDeviceUnavailable || reason == .newDeviceAvailable
            else { return }
            self?.log.add("Sortie audio modifiée")
        })
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.log.add("Alerte mémoire d’iOS")
        })
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.log.add("Changement de \(NightRecorder.thermalText())")
        })
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        switch type {
        case .began:
            interruptions += 1
            log.add("Coupure de l’écoute (appel, Siri, alarme ou autre app audio)")
        case .ended:
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
            log.add("Fin de la coupure · reprise \(shouldResume ? "proposée" : "non proposée") par iOS")
            resume(automatic: true)
        @unknown default:
            break
        }
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.beat()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    private func beat() {
        guard let folder = nightFolder else { return }
        beats += 1
        NightRecorder.append("\(Int(Date().timeIntervalSince1970))\n", to: folder.appendingPathComponent("battements.txt"))
        if beats % 30 == 0 {
            log.add("Toujours à l’écoute · \(segmentCount) tranches · batterie \(NightRecorder.batteryText()) · \(NightRecorder.thermalText())")
        }
        if !engine.isRunning && !needsResume {
            needsResume = true
            log.add("L’écoute s’est arrêtée sans prévenir")
        }
    }

    // MARK: - Outils

    static func append(_ text: String, to url: URL) {
        let data = Data(text.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
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

    static func thermalText() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "température normale"
        case .fair: return "température un peu élevée"
        case .serious: return "température élevée"
        case .critical: return "température critique"
        @unknown default: return "température inconnue"
        }
    }
}
