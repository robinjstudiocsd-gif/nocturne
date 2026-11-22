import DesignSystem
import SwiftUI

/// Données affichées dans les réglages, fournies par l'app.
public struct SettingsInfo: Sendable {
    public let version: String
    public let signatureExpiry: Date?
    public let signatureNeedsRenewal: Bool
    public let launchCount: Int
    public let renewalCount: Int

    public init(version: String, signatureExpiry: Date?, signatureNeedsRenewal: Bool, launchCount: Int, renewalCount: Int) {
        self.version = version
        self.signatureExpiry = signatureExpiry
        self.signatureNeedsRenewal = signatureNeedsRenewal
        self.launchCount = launchCount
        self.renewalCount = renewalCount
    }
}

/// Réglages. Au lot 0 : version, signature et journal de diagnostic ; tous les réglages arrivent au lot 8.
public struct SettingsView: View {
    private let info: SettingsInfo
    private let loadJournal: @Sendable () async -> [String]
    @State private var journal: [String] = []

    public init(info: SettingsInfo, loadJournal: @escaping @Sendable () async -> [String]) {
        self.info = info
        self.loadJournal = loadJournal
    }

    public var body: some View {
        List {
            Section("Signature de l'app") {
                LabeledContent("Valide jusqu'au", value: expiryText)
                if info.signatureNeedsRenewal {
                    Label("Renouvelle l'app avec Sideloadly avant la date d'expiration.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(NocturneColor.amber)
                }
                LabeledContent("Renouvellements", value: "\(info.renewalCount)")
            }
            .listRowBackground(NocturneColor.card)

            Section("À propos") {
                LabeledContent("Version", value: info.version)
                LabeledContent("Lancements", value: "\(info.launchCount)")
            }
            .listRowBackground(NocturneColor.card)

            Section("Journal de diagnostic") {
                if journal.isEmpty {
                    Text("Aucune ligne pour l'instant.")
                        .foregroundStyle(NocturneColor.textSecondary)
                }
                ForEach(Array(journal.reversed().enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(NocturneColor.textSecondary)
                }
            }
            .listRowBackground(NocturneColor.card)
        }
        .scrollContentBackground(.hidden)
        .background(NocturneColor.night)
        .navigationTitle("Réglages")
        .task { journal = await loadJournal() }
    }

    private var expiryText: String {
        guard let expiry = info.signatureExpiry else { return "inconnue" }
        return expiry.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "fr_FR")))
    }
}
