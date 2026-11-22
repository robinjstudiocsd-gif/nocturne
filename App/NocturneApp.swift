import SwiftUI

@main
struct NocturneApp: App {
    private let container: AppContainer?
    private let startupError: String?

    init() {
        do {
            container = try AppContainer.live()
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView(container: container)
                } else {
                    StartupErrorView(message: startupError ?? "erreur inconnue")
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
