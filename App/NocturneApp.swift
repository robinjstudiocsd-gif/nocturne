import SwiftUI

@main
struct NocturneApp: App {
    @StateObject private var lab = LabModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LabView(lab: lab)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                EventLog.shared.add("App au premier plan")
                lab.notifications.refresh()
                lab.checkWidgets()
            case .background:
                EventLog.shared.add("App en arrière-plan")
            default:
                break
            }
        }
    }
}
