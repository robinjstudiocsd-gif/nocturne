import AppSettings
import Foundation
import Persistence
import SettingsFeature
import SleepDomain
import SwiftData

/// Assemblage des dépendances : la seule partie de l'app qui connaît les vrais services.
@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let sessions: any SleepSessionRepository
    let journal: any DiagnosticJournal
    let preferences: AppPreferences
    let signing: SigningStatus
    let renewals: RenewalTracker

    init(modelContainer: ModelContainer, journal: any DiagnosticJournal, defaults: UserDefaults, bundleURL: URL) {
        self.modelContainer = modelContainer
        self.sessions = SwiftDataSleepSessionRepository(container: modelContainer)
        self.journal = journal
        self.preferences = AppPreferences(defaults: defaults)
        self.signing = SigningStatus.read(bundleURL: bundleURL)
        self.renewals = RenewalTracker(defaults: defaults)
    }

    /// Les vrais services, sur disque.
    static func live() throws -> AppContainer {
        let journal = FileDiagnosticJournal(fileURL: try FileDiagnosticJournal.defaultURL())
        let container = AppContainer(
            modelContainer: try PersistenceStack.makeContainer(),
            journal: journal,
            defaults: .standard,
            bundleURL: Bundle.main.bundleURL
        )
        container.recordLaunch()
        return container
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var settingsInfo: SettingsInfo {
        SettingsInfo(
            version: AppContainer.version,
            signatureExpiry: signing.expirationDate,
            signatureNeedsRenewal: signing.needsRenewal(),
            launchCount: renewals.launchCount,
            renewalCount: renewals.renewals.count
        )
    }

    private func recordLaunch() {
        let renewed = renewals.recordLaunch(signing: signing)
        let expiry = signing.expirationDate.map { "valide jusqu’au \($0.formatted(.iso8601))" } ?? "date inconnue"
        journal.record("Lancement n° \(renewals.launchCount) · version \(AppContainer.version) · signature \(expiry)")
        if renewed {
            journal.record("Renouvellement de la signature détecté")
        }
    }
}
