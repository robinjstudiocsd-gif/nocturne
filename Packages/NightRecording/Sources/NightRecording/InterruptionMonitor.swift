#if os(iOS)
import AVFoundation
import CallKit
import Foundation
import SleepDomain

/// Ce qui peut couper l'écoute pendant la nuit.
enum AudioInterruption: Sendable {
    case began(RecordingGap.Cause)
    case ended
    case engineConfigurationChanged
    case mediaServicesReset
}

/// Surveille les appels, Siri, les autres apps audio et les changements de sortie.
@MainActor
final class InterruptionMonitor {
    private var tokens: [NSObjectProtocol] = []
    private let callObserver = CXCallObserver()

    func start(engine: AVAudioEngine, handler: @escaping @MainActor @Sendable (AudioInterruption) -> Void) {
        stop()
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let reasonRaw = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
                switch type {
                case .began:
                    handler(.began(self.cause(reasonRaw: reasonRaw)))
                case .ended:
                    handler(.ended)
                @unknown default:
                    break
                }
            }
        })

        tokens.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            MainActor.assumeIsolated {
                handler(.engineConfigurationChanged)
            }
        })

        tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { _ in
            MainActor.assumeIsolated {
                handler(.mediaServicesReset)
            }
        })
    }

    func stop() {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens.removeAll()
    }

    /// Cause probable d'une coupure : micro coupé, appel en cours, ou autre son (Siri, alarme, autre app).
    private func cause(reasonRaw: UInt?) -> RecordingGap.Cause {
        if let reasonRaw, AVAudioSession.InterruptionReason(rawValue: reasonRaw) == .builtInMicMuted {
            return .microphoneUnavailable
        }
        if callObserver.calls.contains(where: { !$0.hasEnded }) {
            return .phoneCall
        }
        return .otherAudio
    }
}
#endif
