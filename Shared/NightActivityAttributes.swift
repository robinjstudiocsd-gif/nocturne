import ActivityKit
import Foundation

/// Données de la Live Activity « Nuit en cours », partagées entre l'app et l'extension des widgets.
struct NightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var alarmDate: Date?
        var isRinging: Bool
    }

    var startDate: Date
}
