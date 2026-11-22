import AVFoundation
import Foundation
import UserNotifications

/// Réveil d'iOS 18 : l'app joue elle-même l'alarme pendant l'écoute,
/// avec une notification de secours une minute plus tard si l'app ne peut pas sonner.
final class AlarmController: ObservableObject {
    static let backupIdentifier = "nocturne.reveil.secours"

    @Published var hour: Int {
        didSet { UserDefaults.standard.set(hour, forKey: "alarm.hour") }
    }
    @Published var minute: Int {
        didSet { UserDefaults.standard.set(minute, forKey: "alarm.minute") }
    }
    @Published private(set) var nextAlarm: Date?
    @Published private(set) var isRinging = false

    private var checkTimer: Timer?
    private var rampTimer: Timer?
    private weak var recorder: NightRecorder?
    private let log = EventLog.shared
    private let defaults = UserDefaults.standard

    init() {
        hour = (UserDefaults.standard.object(forKey: "alarm.hour") as? Int) ?? 7
        minute = (UserDefaults.standard.object(forKey: "alarm.minute") as? Int) ?? 0
    }

    /// Heure du réveil, pour le sélecteur d'heure.
    var alarmTime: Date {
        get {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = parts.hour ?? 7
            minute = parts.minute ?? 0
        }
    }

    /// Résultat du dernier réveil, pour le rapport.
    var lastResult: String {
        guard let planned = defaults.object(forKey: "alarm.lastPlanned") as? Date else { return "pas encore testée" }
        var text = "prévue à \(Format.time(planned))"
        if let fired = defaults.object(forKey: "alarm.lastFired") as? Date {
            text += ", jouée à \(fired.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(Format.french))) (retard \(Int(fired.timeIntervalSince(planned).rounded())) s)"
            if let stopped = defaults.object(forKey: "alarm.lastStopped") as? Date {
                text += ", arrêtée après \(Int(stopped.timeIntervalSince(fired).rounded())) s"
            }
        } else {
            text += ", pas jouée par l’app"
        }
        return text
    }

    // MARK: - Programmer

    func arm(recorder: NightRecorder, testDelay: TimeInterval?) {
        self.recorder = recorder
        let date = testDelay.map { Date().addingTimeInterval($0) } ?? AlarmController.nextDate(hour: hour, minute: minute)
        nextAlarm = date
        defaults.set(date, forKey: "alarm.lastPlanned")
        defaults.removeObject(forKey: "alarm.lastFired")
        defaults.removeObject(forKey: "alarm.lastStopped")
        scheduleBackup(at: date.addingTimeInterval(60))
        checkTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
        log.add("Réveil programmé à \(Format.dateTime(date)) · secours une minute plus tard")
    }

    func disarm() {
        checkTimer?.invalidate()
        checkTimer = nil
        rampTimer?.invalidate()
        rampTimer = nil
        nextAlarm = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AlarmController.backupIdentifier])
    }

    static func nextDate(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if date <= now {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    // MARK: - Sonner

    private func check() {
        guard let next = nextAlarm, !isRinging, Date() >= next else { return }
        ring()
    }

    private func ring() {
        guard let recorder, recorder.isRunning else {
            log.add("Heure du réveil atteinte, mais l’écoute n’était plus active")
            return
        }
        guard let buffer = AlarmTone.makeBuffer() else { return }
        let now = Date()
        isRinging = true
        defaults.set(now, forKey: "alarm.lastFired")
        let delay = Int(now.timeIntervalSince(nextAlarm ?? now).rounded())
        log.add("Réveil joué par l’app · retard \(delay) s · volume du téléphone \(Int((AVAudioSession.sharedInstance().outputVolume * 100).rounded())) %")

        if !recorder.engine.isRunning {
            try? recorder.engine.start()
        }
        let player = recorder.player
        player.stop()
        player.volume = 0.15
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.play()

        rampTimer?.invalidate()
        let ramp = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, self.isRinging else {
                timer.invalidate()
                return
            }
            player.volume = min(1, player.volume + 0.03)
        }
        RunLoop.main.add(ramp, forMode: .common)
        rampTimer = ramp

        // L'app sonne : la notification de secours devient inutile,
        // une notification silencieuse permet d'ouvrir l'app depuis l'écran verrouillé.
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [AlarmController.backupIdentifier])
        let content = UNMutableNotificationContent()
        content.title = "Réveil"
        content.body = "Ouvre Nocturne pour arrêter le réveil."
        center.add(UNNotificationRequest(identifier: "nocturne.reveil.ouvrir", content: content, trigger: nil))

        LiveActivityController.shared.update(ringing: true, alarm: nextAlarm)
    }

    func stopRinging() {
        guard isRinging else { return }
        isRinging = false
        rampTimer?.invalidate()
        rampTimer = nil
        recorder?.player.stop()
        let now = Date()
        defaults.set(now, forKey: "alarm.lastStopped")
        if let fired = defaults.object(forKey: "alarm.lastFired") as? Date {
            log.add("Réveil arrêté après \(Int(now.timeIntervalSince(fired).rounded())) s")
        }
    }

    private func scheduleBackup(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Réveil de secours"
        content.body = "Nocturne n’a pas pu jouer l’alarme : il est l’heure."
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let request = UNNotificationRequest(identifier: AlarmController.backupIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                EventLog.shared.add("Notification de secours refusée : \(error.localizedDescription)")
            }
        }
    }
}
