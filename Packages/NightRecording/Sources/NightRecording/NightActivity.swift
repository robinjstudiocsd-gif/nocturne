#if os(iOS)
import ActivityKit
import Foundation
import SleepDomain

extension NightActivityAttributes: @retroactive ActivityAttributes {}

/// Une Live Activity n'est pas « Sendable » : on la transporte ainsi vers les tâches d'ActivityKit,
/// qui la mettent à jour sans toucher à l'interface.
private struct ActivityHandle: @unchecked Sendable {
    let activity: Activity<NightActivityAttributes>
}

/// Live Activity « Nuit en cours » sur l'écran verrouillé.
@MainActor
final class NightActivityController {
    private var activity: Activity<NightActivityAttributes>?

    var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Affiche la Live Activity ; renvoie faux si elle est désactivée ou refusée.
    func start(session: SleepSession, alarm: Date?) -> Bool {
        guard isEnabled else { return false }
        let attributes = NightActivityAttributes(startDate: session.times.bedtime ?? session.createdAt, kind: session.kind)
        let state = NightActivityAttributes.ContentState(isListening: session.recordingMode != .off, alarmDate: alarm, isRinging: false)
        do {
            activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
            return true
        } catch {
            return false
        }
    }

    func update(_ state: NightActivityAttributes.ContentState) {
        guard let activity else { return }
        let handle = ActivityHandle(activity: activity)
        Task.detached {
            await handle.activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        let state = activity.content.state
        let handle = ActivityHandle(activity: activity)
        Task.detached {
            await handle.activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    /// Ferme les Live Activities restées affichées après une fermeture de l'app.
    func endStale() {
        for stale in Activity<NightActivityAttributes>.activities where stale.id != activity?.id {
            let handle = ActivityHandle(activity: stale)
            Task.detached {
                await handle.activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
