import Foundation
import UserNotifications

/// Test n° 3 : autorisation et réception des notifications locales.
final class NotificationProbe: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var status = "non demandée"
    @Published private(set) var lastReceived: String?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        refresh()
    }

    func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let text: String
            switch settings.authorizationStatus {
            case .authorized: text = "autorisées"
            case .denied: text = "refusées (Réglages > Nocturne > Notifications)"
            case .notDetermined: text = "non demandée"
            case .provisional: text = "provisoires"
            case .ephemeral: text = "temporaires"
            @unknown default: text = "état inconnu"
            }
            DispatchQueue.main.async { self.status = text }
        }
    }

    func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            var text = "Notifications \(granted ? "autorisées" : "refusées")"
            if let error { text += " (\(error.localizedDescription))" }
            EventLog.shared.add(text)
            self.refresh()
        }
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Test Nocturne"
        content.body = "Si tu lis ceci, les notifications fonctionnent."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "nocturne.test", content: content, trigger: trigger)) { error in
            if let error {
                EventLog.shared.add("Notification de test refusée : \(error.localizedDescription)")
            }
        }
        EventLog.shared.add("Notification de test programmée dans 10 s")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let title = notification.request.content.title
        EventLog.shared.add("Notification reçue, app ouverte : \(title)")
        DispatchQueue.main.async { self.lastReceived = title }
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let title = response.notification.request.content.title
        EventLog.shared.add("Notification touchée : \(title)")
        DispatchQueue.main.async { self.lastReceived = title }
        completionHandler()
    }
}
