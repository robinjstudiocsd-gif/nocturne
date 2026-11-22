import AVFoundation
import SwiftUI
import UIKit
import WidgetKit

/// Coordonne les sept essais de la phase 0.
final class LabModel: ObservableObject {
    let recorder = NightRecorder()
    let alarm = AlarmController()
    let notifications = NotificationProbe()
    let health = HealthProbe()
    let launch = LaunchTracker()

    @Published private(set) var lastNight: NightSummary?
    @Published private(set) var widgetStatus = "pas encore vérifié"
    @Published var message: String?

    init() {
        lastNight = NightStore.latestSummary()
        if let night = lastNight, !night.closedNormally {
            EventLog.shared.add("Nuit précédente non terminée normalement · dernier battement \(night.lastBeat.map { Format.time($0) } ?? "aucun")")
        }
        checkWidgets()
    }

    var liveActivityStatus: String {
        LiveActivityController.shared.isEnabled ? "autorisées" : "désactivées (Réglages > Nocturne)"
    }

    func startNight(testAlarmIn delay: TimeInterval? = nil) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    self.message = "Micro refusé : autorise-le dans Réglages > Nocturne."
                    EventLog.shared.add("Micro refusé")
                    return
                }
                do {
                    try self.recorder.start()
                    self.alarm.arm(recorder: self.recorder, testDelay: delay)
                    LiveActivityController.shared.start(startDate: self.recorder.startDate ?? Date(), alarm: self.alarm.nextAlarm)
                    self.message = nil
                } catch {
                    self.message = "Démarrage impossible : \(error.localizedDescription)"
                    EventLog.shared.add("Démarrage impossible : \(error.localizedDescription)")
                }
            }
        }
    }

    func stopNight(reason: String) {
        alarm.stopRinging()
        alarm.disarm()
        recorder.stop(reason: reason)
        LiveActivityController.shared.end()
        lastNight = NightStore.latestSummary()
    }

    func checkWidgets() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            let text: String
            switch result {
            case .success(let widgets):
                text = widgets.isEmpty ? "aucun widget Nocturne sur l’écran d’accueil" : "\(widgets.count) widget(s) Nocturne affiché(s)"
            case .failure(let error):
                text = "vérification impossible : \(error.localizedDescription)"
            }
            DispatchQueue.main.async { self.widgetStatus = text }
        }
    }

    /// Rapport texte à coller dans la conversation : aucun identifiant ni mot de passe.
    func report() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var lines: [String] = []
        lines.append("Rapport Nocturne · phase 0")
        lines.append("Version \(version) (\(build)) · iOS \(UIDevice.current.systemVersion) · \(Format.dateTime(Date()))")
        lines.append("")
        if let night = lastNight {
            lines.append("1. Nuit écran verrouillé : " + NightStore.describe(night))
        } else {
            lines.append("1. Nuit écran verrouillé : pas encore de nuit")
        }
        lines.append("2. Alarme d’iOS 18 : " + alarm.lastResult)
        lines.append("3. Notifications : " + notifications.status + (notifications.lastReceived.map { " · dernière reçue : \($0)" } ?? ""))
        lines.append("4. Live Activity : " + liveActivityStatus)
        lines.append("5. Widget : " + widgetStatus)
        lines.append("6. Santé : " + health.status)
        for night in health.nights.prefix(3) {
            lines.append("   · " + night)
        }
        let expiry = launch.expiry.map { "signature valide jusqu’au \(Format.dateTime($0))" } ?? "date de signature introuvable"
        lines.append("7. Renouvellement : \(expiry) · \(launch.renewals.count) renouvellement(s) détecté(s) · première ouverture \(Format.dateTime(launch.firstLaunch)) · \(launch.launchCount) lancements · \(NightStore.allNightFolders().count) nuit(s) gardée(s)")
        lines.append("")
        lines.append("Journal (40 dernières lignes) :")
        lines.append(contentsOf: EventLog.shared.lastLines(40))
        return lines.joined(separator: "\n")
    }
}
