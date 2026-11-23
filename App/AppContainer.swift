import AppSettings
import Foundation
import JournalFeature
import NightFeature
import NightRecording
import Persistence
import SettingsFeature
import SleepDomain
import SwiftData

/// Assemblage des dépendances : la seule partie de l'app qui connaît les vrais services.
@MainActor
final class AppContainer {
    /// Qualité de l'audio enregistré (étude : 32 kbit/s à 24 kHz par défaut).
    static let audioQuality = AudioQuality.standard

    let modelContainer: ModelContainer
    let sessions: any SleepSessionRepository
    let recordings: any RecordingRepository
    let eveningLogs: any EveningLogRepository
    let events: any NightEventRepository
    let lifecycle: SessionLifecycle
    let night: NightSessionController
    let journal: any DiagnosticJournal
    let preferences: AppPreferences
    let signing: SigningStatus
    let renewals: RenewalTracker
    let preflight: DevicePreflight
    let eraser: RecordingEraser

    init(modelContainer: ModelContainer, journal: any DiagnosticJournal, defaults: UserDefaults, bundleURL: URL, storage: RecordingStorage) {
        let sessions = SwiftDataSleepSessionRepository(container: modelContainer)
        let recordings = SwiftDataRecordingRepository(container: modelContainer)
        let events = SwiftDataNightEventRepository(container: modelContainer)
        let lifecycle = SessionLifecycle(repository: sessions)
        let signing = SigningStatus.read(bundleURL: bundleURL)
        self.modelContainer = modelContainer
        self.sessions = sessions
        self.recordings = recordings
        self.eveningLogs = SwiftDataEveningLogRepository(container: modelContainer)
        self.events = events
        self.lifecycle = lifecycle
        self.night = NightSessionController(lifecycle: lifecycle, recordings: recordings, events: events, storage: storage, journal: journal, quality: AppContainer.audioQuality)
        self.journal = journal
        self.preferences = AppPreferences(defaults: defaults)
        self.signing = signing
        self.renewals = RenewalTracker(defaults: defaults)
        self.preflight = DevicePreflight(storage: storage, signatureExpiry: signing.expirationDate)
        self.eraser = RecordingEraser(storage: storage, recordings: recordings, events: events)
    }

    /// Modèle de vue du Journal : liste, fiches, modifications et ajouts.
    func makeJournalModel() -> JournalViewModel {
        JournalViewModel(dependencies: JournalDependencies(
            sessions: sessions,
            recordings: recordings,
            eveningLogs: eveningLogs,
            lifecycle: lifecycle,
            eraser: eraser
        ))
    }

    /// Modèle de vue de l'onglet Nuit, partagé par l'écran de préparation et l'écran de nuit.
    func makeNightModel() -> NightViewModel {
        NightViewModel(
            service: night,
            preflight: preflight,
            preferences: preferences,
            lifecycle: lifecycle,
            eveningLogs: eveningLogs,
            quality: AppContainer.audioQuality
        )
    }

    /// Les vrais services, sur disque.
    static func live() throws -> AppContainer {
        let journal = FileDiagnosticJournal(fileURL: try FileDiagnosticJournal.defaultURL())
        let container = AppContainer(
            modelContainer: try PersistenceStack.makeContainer(),
            journal: journal,
            defaults: .standard,
            bundleURL: Bundle.main.bundleURL,
            storage: try RecordingStorage.applicationSupport()
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
