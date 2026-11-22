import ActivityKit
import Foundation

/// Test n° 4 : Live Activity « Nuit en cours » sur l'écran verrouillé.
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<NightActivityAttributes>?

    var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(startDate: Date, alarm: Date?) {
        guard isEnabled else {
            EventLog.shared.add("Live Activity désactivée dans les réglages de l’iPhone")
            return
        }
        let attributes = NightActivityAttributes(startDate: startDate)
        let state = NightActivityAttributes.ContentState(alarmDate: alarm, isRinging: false)
        do {
            activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
            EventLog.shared.add("Live Activity affichée")
        } catch {
            EventLog.shared.add("Live Activity impossible : \(error.localizedDescription)")
        }
    }

    func update(ringing: Bool, alarm: Date?) {
        guard let activity else { return }
        let state = NightActivityAttributes.ContentState(alarmDate: alarm, isRinging: ringing)
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        let state = activity.content.state
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        EventLog.shared.add("Live Activity terminée")
    }
}
